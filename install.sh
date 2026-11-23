
#!/data/data/com.termux/files/usr/bin/bash

set -e

PROJECT="$HOME/FahzyAIScanner"
cd "$PROJECT"

mkdir -p app/src/main/java/com/fahzy/scanner
mkdir -p app/src/main/assets
mkdir -p .github/workflows

cat > settings.gradle <<'EOF'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "FahzyAIScanner"
include(":app")
EOF

cat > build.gradle <<'EOF'
plugins {
    id 'com.android.application' version '8.6.1' apply false
}
EOF

cat > gradle.properties <<'EOF'
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
EOF

cat > app/build.gradle <<'EOF'
plugins {
    id 'com.android.application'
}

android {
    namespace 'com.fahzy.scanner'
    compileSdk 35

    defaultConfig {
        applicationId 'com.fahzy.scanner'
        minSdk 23
        targetSdk 35
        versionCode 1
        versionName '1.0'
    }
}
EOF

cat > app/src/main/AndroidManifest.xml <<'EOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <application
        android:theme="@android:style/Theme.Material.NoActionBar"
        android:label="Fahzy AI Scanner"
        android:usesCleartextTraffic="false">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
EOF

cat > app/src/main/java/com/fahzy/scanner/MainActivity.java <<'EOF'
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
EOF

cat > app/src/main/assets/index.html <<'EOF'
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Fahzy AI Scanner</title>
<link rel="stylesheet" href="style.css">
</head>
<body>

<div id="login" class="screen">
  <div class="login-box">
    <div class="logo">✦</div>
    <h1>Fahzy <span>AI</span></h1>
    <p>Smart Study Assistant</p>
    <input id="username" placeholder="Nama pengguna">
    <input id="password" type="password" placeholder="Password">
    <button onclick="login()">Masuk</button>
    <small>Login lokal untuk perangkat ini</small>
  </div>
</div>

<div id="app" class="hidden">
  <header>
    <div>
      <small>WELCOME BACK</small>
      <h2>Fahzy <span>AI</span></h2>
    </div>
    <button class="icon" onclick="showPage('settings')">⚙</button>
  </header>

  <main>
    <section id="home" class="page">
      <div class="hero">
        <div class="tag">✦ AI POWERED</div>
        <h1>Belajar lebih<br><span>cerdas.</span></h1>
        <p>Foto soalmu. Biarkan AI membantu memahami jawabannya.</p>
        <button onclick="showPage('scanner')">Mulai Scan ↗</button>
      </div>

      <h3>Fitur utama</h3>
      <div class="feature">
        <div>📷</div>
        <section><b>AI Scanner</b><p>Analisis soal dari gambar.</p></section>
      </div>
      <div class="feature">
        <div>🧠</div>
        <section><b>Pembahasan pintar</b><p>Pelajari langkah penyelesaiannya.</p></section>
      </div>
      <div class="feature">
        <div>⚡</div>
        <section><b>Gemini AI</b><p>Analisis soal menggunakan AI.</p></section>
      </div>
    </section>

    <section id="scanner" class="page hidden">
      <h2>AI Scanner</h2>
      <p class="muted">Pilih foto soal yang ingin dianalisis.</p>
      <div class="upload">
        <div style="font-size:40px">📸</div>
        <p>Masukkan gambar soal</p>
        <input type="file" id="photo" accept="image/*">
      </div>
      <img id="preview" class="preview hidden">
      <textarea id="prompt" placeholder="Contoh: Jelaskan langkah penyelesaiannya..."></textarea>
      <button id="scanBtn" onclick="scan()">✦ Analisis soal</button>
      <div id="loading" class="hidden">
        <div class="loader"></div>
        <p>AI sedang menganalisis...</p>
      </div>
      <div id="result" class="result hidden">
        <h3>✦ Hasil analisis</h3>
        <pre id="answer"></pre>
        <button class="secondary" onclick="copyAnswer()">Salin jawaban</button>
      </div>
    </section>

    <section id="settings" class="page hidden">
      <h2>Pengaturan</h2>
      <div class="panel">
        <h3>Gemini API</h3>
        <p class="muted">Masukkan API Key milikmu.</p>
        <input id="apiKey" type="password" placeholder="Gemini API Key">
        <button onclick="saveKey()">Simpan API Key</button>
        <p class="muted" id="keyStatus"></p>
      </div>
      <div class="panel">
        <h3>Akun</h3>
        <p id="account"></p>
        <button class="danger" onclick="logout()">Keluar</button>
      </div>
      <div class="panel">
        <h3>Tentang aplikasi</h3>
        <p>Fahzy AI Scanner v1.0</p>
        <p class="muted">Java + WebView + Gemini AI</p>
      </div>
    </section>
  </main>

  <nav>
    <button onclick="showPage('home')">⌂<small>Home</small></button>
    <button onclick="showPage('scanner')">◎<small>Scanner</small></button>
    <button onclick="showPage('settings')">⚙<small>Settings</small></button>
  </nav>
</div>
<script src="app.js"></script>
</body>
</html>
EOF

cat > app/src/main/assets/style.css <<'EOF'
*{box-sizing:border-box}
body{margin:0;background:#090b12;color:#f5f5fa;
font-family:Arial,sans-serif}
:root{--purple:#9272ff;--card:#151827;--muted:#9298aa}
.hidden{display:none!important}
.screen{min-height:100vh;display:grid;place-items:center;padding:25px}
.login-box{width:100%;max-width:380px;text-align:center;
animation:up .6s ease}
.logo{font-size:48px;color:var(--purple)}
h1 span,h2 span{color:var(--purple)}
input,textarea{width:100%;padding:15px;margin:9px 0;
background:#171b2b;border:1px solid #282e42;
border-radius:12px;color:white;outline:none}
button{border:0;border-radius:12px;padding:15px;
background:var(--purple);color:white;font-weight:bold;
cursor:pointer}
.login-box button{width:100%;margin-top:12px}
small,.muted{color:var(--muted)}
header{padding:24px;display:flex;align-items:center;
justify-content:space-between}
header h2{margin:5px 0}
.icon{font-size:21px;background:var(--card)}
main{padding:0 20px 100px}
.page{animation:up .35s ease}
.hero{padding:25px;border-radius:23px;
background:linear-gradient(140deg,#272044,#171a30);
margin-bottom:30px}
.hero h1{font-size:38px;line-height:1.15}
.hero h1 span{color:#ad98ff}
.hero p,.feature p{color:#b2b5c4;line-height:1.6}
.tag{font-size:11px;color:#c4b5ff}
.hero button{width:100%;margin-top:15px}
.feature,.panel{display:flex;gap:15px;
background:var(--card);padding:17px;border-radius:16px;
margin:12px 0}
.feature>div{font-size:26px}
.feature p{margin:6px 0 0}
.feature section{flex:1}
.upload{padding:30px 15px;text-align:center;
border:1px dashed #66549c;border-radius:18px;
background:#141626;margin:20px 0}
.upload input{border:0}
.preview{width:100%;max-height:280px;object-fit:contain;
border-radius:14px;margin:10px 0}
textarea{min-height:85px;resize:vertical}
#scanBtn{width:100%}
.result,.panel{display:block;background:var(--card);
padding:18px;border-radius:16px;margin-top:18px}
pre{white-space:pre-wrap;word-wrap:break-word;
font-family:Arial;line-height:1.7;color:#e0e1eb}
.secondary{background:#34304b}
.danger{background:#9c3854}
nav{position:fixed;bottom:0;left:0;right:0;
display:flex;justify-content:space-around;
padding:12px;background:#111522;border-top:1px solid #252a3a}
nav button{background:transparent;font-size:21px;
display:flex;flex-direction:column;align-items:center;gap:4px}
nav small{font-size:10px}
.loader{width:34px;height:34px;border:3px solid #39334f;
border-top-color:var(--purple);border-radius:50%;
animation:spin .8s linear infinite;margin:20px auto}
@keyframes spin{to{transform:rotate(360deg)}}
@keyframes up{from{opacity:0;transform:translateY(12px)}
to{opacity:1;transform:translateY(0)}}
EOF

cat > app/src/main/assets/app.js <<'EOF'
let selectedFile = null;
let requestNumber = 0;

const $ = id => document.getElementById(id);

function login(){
  const user = $('username').value.trim();
  const pass = $('password').value;

  if(!user || !pass){
    alert('Isi nama pengguna dan password!');
    return;
  }

  localStorage.setItem('user',user);
  openApp();
}

function openApp(){
  $('login').classList.add('hidden');
  $('app').classList.remove('hidden');
  $('account').textContent =
    'Login sebagai: ' + localStorage.getItem('user');
  $('apiKey').value = Android.getApiKey();
}

function logout(){
  localStorage.removeItem('user');
  $('app').classList.add('hidden');
  $('login').classList.remove('hidden');
}

function showPage(name){
  document.querySelectorAll('.page').forEach(p=>
    p.classList.add('hidden'));
  $(name).classList.remove('hidden');
  window.scrollTo(0,0);
}

function saveKey(){
  const key = $('apiKey').value.trim();
  if(!key){alert('API Key masih kosong!');return;}
  Android.saveApiKey(key);
  $('keyStatus').textContent='API Key tersimpan di perangkat.';
  alert('API Key berhasil disimpan.');
}

$('photo').addEventListener('change',e=>{
  selectedFile=e.target.files[0];
  if(!selectedFile)return;

  $('preview').src=URL.createObjectURL(selectedFile);
  $('preview').classList.remove('hidden');
});

async function scan(){
  if(!selectedFile){
    alert('Pilih gambar soal terlebih dahulu!');
    return;
  }

  if(!Android.getApiKey()){
    alert('Masukkan API Key di pengaturan!');
    showPage('settings');
    return;
  }

  $('loading').classList.remove('hidden');
  $('result').classList.add('hidden');
  $('scanBtn').disabled=true;

  try{
    const resized = await resizeImage(selectedFile);
    const reader = new FileReader();

    reader.onload=()=>{
      const base64=reader.result.split(',')[1];
      const id=String(++requestNumber);

      window.pendingRequest=id;
      Android.analyze(
        base64,
        'image/jpeg',
        $('prompt').value || 'Jawab soal dan jelaskan.',
        id
      );
    };

    reader.onerror=()=>{
      finishError('Gagal membaca gambar.');
    };

    reader.readAsDataURL(resized);
  }catch(e){
    finishError(e.message);
  }
}

function resizeImage(file){
  return new Promise((resolve,reject)=>{
    const img=new Image();
    const url=URL.createObjectURL(file);

    img.onload=()=>{
      const canvas=document.createElement('canvas');
      const scale=Math.min(1,1600/Math.max(img.width,img.height));
      canvas.width=Math.round(img.width*scale);
      canvas.height=Math.round(img.height*scale);

      canvas.getContext('2d').drawImage(
        img,0,0,canvas.width,canvas.height);

      canvas.toBlob(blob=>{
        URL.revokeObjectURL(url);
        if(blob)resolve(blob);
        else reject(new Error('Gagal memproses gambar'));
      },'image/jpeg',0.82);
    };

    img.onerror=()=>reject(new Error('Gambar tidak valid'));
    img.src=url;
  });
}

window.onAIResult=raw=>{
  try{
    const data=JSON.parse(raw);
    if(data.id!==window.pendingRequest)return;

    if(data.error)finishError(data.error);
    else{
      $('answer').textContent=data.answer || 'Jawaban kosong.';
      $('result').classList.remove('hidden');
      finishLoading();
    }
  }catch(e){
    finishError('Gagal membaca hasil AI.');
  }
};

function finishLoading(){
  $('loading').classList.add('hidden');
  $('scanBtn').disabled=false;
}

function finishError(message){
  finishLoading();
  alert('Terjadi kesalahan: '+message);
}

function copyAnswer(){
  const text=$('answer').textContent;
  if(navigator.clipboard){
    navigator.clipboard.writeText(text)
      .then(()=>alert('Jawaban disalin!'))
      .catch(()=>alert(text));
  }else alert(text);
}

if(localStorage.getItem('user'))openApp();
EOF

cat > .github/workflows/build.yml <<'EOF'
name: Build Fahzy AI Scanner

on:
  workflow_dispatch:
  push:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - uses: android-actions/setup-android@v3

      - name: Install Android SDK
        run: sdkmanager "platforms;android-35" "build-tools;35.0.0"

      - name: Setup Gradle
        uses: gradle/actions/setup-gradle@v4
        with:
          gradle-version: '8.7'

      - name: Build APK
        run: gradle assembleDebug

      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: Fahzy-AI-Scanner-APK
          path: app/build/outputs/apk/debug/app-debug.apk
EOF

echo ""
echo "===================================="
echo " FAHZY AI SCANNER BERHASIL DIBUAT"
echo "===================================="
echo "Lokasi proyek: $PROJECT"
echo "Source code sudah siap."
echo "Build APK melalui GitHub Actions."
