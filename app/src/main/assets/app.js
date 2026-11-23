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
