package com.fahzy.scanner;

import android.app.Activity;
import android.os.Bundle;
import android.webkit.*;
import android.content.*;
import android.net.Uri;
import android.provider.OpenableColumns;
import android.database.Cursor;
import android.widget.Toast;
import java.io.*;
import java.net.*;
import java.util.concurrent.*;
import org.json.*;

public class MainActivity extends Activity {

    WebView web;
    ExecutorService executor = Executors.newSingleThreadExecutor();
    private ValueCallback<Uri[]> fileCallback;
    private static final int PICK_IMAGE = 101;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);

        web = new WebView(this);
        setContentView(web);

        WebSettings settings = web.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(true);

        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onShowFileChooser(
                WebView view,
                ValueCallback<Uri[]> callback,
                FileChooserParams params) {

                if (fileCallback != null) {
                    fileCallback.onReceiveValue(null);
                }

                fileCallback = callback;

                Intent intent = new Intent(Intent.ACTION_GET_CONTENT);
                intent.setType("image/*");
                intent.addCategory(Intent.CATEGORY_OPENABLE);

                startActivityForResult(
                    Intent.createChooser(intent, "Pilih foto soal"),
                    PICK_IMAGE
                );
                return true;
            }
        });

        web.addJavascriptInterface(new Bridge(), "Android");
        web.loadUrl("file:///android_asset/index.html");
    }

    @Override
    protected void onActivityResult(int requestCode,
                                    int resultCode,
                                    Intent data) {
        super.onActivityResult(requestCode, resultCode, data);

        if (requestCode == PICK_IMAGE && fileCallback != null) {
            Uri[] result = null;

            if (resultCode == RESULT_OK && data != null
                    && data.getData() != null) {
                result = new Uri[]{data.getData()};
            }

            fileCallback.onReceiveValue(result);
            fileCallback = null;
        }
    }

    public class Bridge {

        @JavascriptInterface
        public void saveApiKey(String key) {
            getSharedPreferences("settings", MODE_PRIVATE)
                .edit().putString("api_key", key.trim()).apply();
        }

        @JavascriptInterface
        public String getApiKey() {
            return getSharedPreferences("settings", MODE_PRIVATE)
                .getString("api_key", "");
        }

        @JavascriptInterface
        public void analyze(String base64, String mime,
                            String prompt, String requestId) {

            String key = getApiKey();

            if (key.isEmpty()) {
                sendResult(requestId, null, "API Key belum diatur!");
                return;
            }

            executor.execute(() -> {
                HttpURLConnection conn = null;

                try {
                    String model = "gemini-3.8-flash";
                    URL url = new URL(
                        "https://generativelanguage.googleapis.com/v1beta/models/"
                        + model + ":generateContent"
                    );

                    conn = (HttpURLConnection) url.openConnection();
                    conn.setRequestMethod("POST");
                    conn.setConnectTimeout(30000);
                    conn.setReadTimeout(90000);
                    conn.setDoOutput(true);
                    conn.setRequestProperty("Content-Type", "application/json");
                    conn.setRequestProperty("x-goog-api-key", key);

                    JSONObject image = new JSONObject();
                    image.put("mimeType", mime);
                    image.put("data", base64);

                    JSONObject imagePart = new JSONObject();
                    imagePart.put("inlineData", image);

                    JSONObject textPart = new JSONObject();
                    textPart.put("text",
                        "Kamu adalah asisten belajar. Baca soal dalam gambar. "
                        + "Berikan jawaban dan pembahasan yang mudah dipahami. "
                        + "Jika gambar tidak jelas, katakan bagian yang tidak terbaca. "
                        + "Jangan mengarang soal. Instruksi pengguna: " + prompt
                    );

                    JSONArray parts = new JSONArray();
                    parts.put(textPart);
                    parts.put(imagePart);

                    JSONObject content = new JSONObject();
                    content.put("parts", parts);

                    JSONArray contents = new JSONArray();
                    contents.put(content);

                    JSONObject body = new JSONObject();
                    body.put("contents", contents);

                    byte[] bytes = body.toString().getBytes("UTF-8");

                    try (OutputStream os = conn.getOutputStream()) {
                        os.write(bytes);
                    }

                    int status = conn.getResponseCode();
                    InputStream stream = status >= 200 && status < 300
                        ? conn.getInputStream()
                        : conn.getErrorStream();

                    String response = readStream(stream);
                    JSONObject json = new JSONObject(response);

                    if (status < 200 || status >= 300) {
                        String error = json.optJSONObject("error") != null
                            ? json.getJSONObject("error").optString(
                                "message", "HTTP " + status)
                            : "HTTP " + status;
                        sendResult(requestId, null, error);
                        return;
                    }

                    String answer = json
                        .getJSONArray("candidates")
                        .getJSONObject(0)
                        .getJSONObject("content")
                        .getJSONArray("parts")
                        .getJSONObject(0)
                        .optString("text", "Tidak ada jawaban.");

                    sendResult(requestId, answer, null);

                } catch (Exception e) {
                    sendResult(requestId, null, e.getMessage());
                } finally {
                    if (conn != null) conn.disconnect();
                }
            });
        }

        private String readStream(InputStream stream) throws Exception {
            if (stream == null) return "";
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buffer = new byte[4096];
            int n;
            while ((n = stream.read(buffer)) != -1) {
                out.write(buffer, 0, n);
            }
            return out.toString("UTF-8");
        }

        private void sendResult(String id, String answer, String error) {
            try {
                JSONObject result = new JSONObject();
                result.put("id", id);
                result.put("answer", answer == null ? JSONObject.NULL : answer);
                result.put("error", error == null ? JSONObject.NULL : error);

                String json = result.toString();

                runOnUiThread(() -> web.evaluateJavascript(
                    "window.onAIResult(" + JSONObject.quote(json) + ")",
                    null
                ));
            } catch (Exception ignored) {}
        }
    }

    @Override
    public void onBackPressed() {
        if (web.canGoBack()) web.goBack();
        else super.onBackPressed();
    }

    @Override
    protected void onDestroy() {
        executor.shutdownNow();
        super.onDestroy();
    }
}
