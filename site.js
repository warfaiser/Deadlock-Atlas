'use strict';
const config=window.ATLAS_SITE||{};
const repoPattern=/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
function repository(host,path){if(config.repository&&repoPattern.test(config.repository))return config.repository;if(host.endsWith('.github.io')){const user=host.slice(0,-10);const segment=path.split('/').filter(Boolean)[0];const repo=segment&&!segment.includes('.html')?segment:host;const value=user+'/'+repo;return repoPattern.test(value)?value:null}return null}
const repo=repository(location.hostname,location.pathname);
const download=document.querySelector('#download-link'),release=document.querySelector('#release-link'),note=document.querySelector('#publish-note');
if(repo){const base='https://github.com/'+repo+'/releases';download.href=base+'/latest/download/Deadlock-Atlas.exe';release.href=base+'/latest';release.target='_blank';release.rel='noopener noreferrer';release.hidden=false;note.hidden=true}else if(location.hostname==='localhost'||location.hostname==='127.0.0.1'||location.hostname.endsWith('.e2b.app')){download.href='/download';note.textContent='Предпросмотр: кнопка скачивает подготовленный EXE. Публичный сайт появится после публикации в твоём GitHub.'}else{download.href='#publish-note';note.textContent='Для включения скачивания опубликуй сайт на GitHub Pages или укажи repository в config.js.'}
const descriptions={heroes:'Скриншот: каталог героев Deadlock Atlas',build:'Скриншот: сборка Инфернуса, предметы и порядок покупок'};
const tabs=[...document.querySelectorAll('[data-view]')];
function activate(tab,focus=false){tabs.forEach(t=>{t.setAttribute('aria-selected',String(t===tab));t.tabIndex=t===tab?0:-1});const image=document.querySelector('#app-screen');image.src='assets/app-'+tab.dataset.view+'.webp';image.alt=descriptions[tab.dataset.view];document.querySelector('#app-panel').setAttribute('aria-labelledby',tab.id);if(focus)tab.focus()}
tabs.forEach((tab,i)=>{tab.addEventListener('click',()=>activate(tab));tab.addEventListener('keydown',e=>{if(['ArrowLeft','ArrowRight','Home','End'].includes(e.key)){e.preventDefault();const target=e.key==='Home'?0:e.key==='End'?tabs.length-1:(i+(e.key==='ArrowRight'?1:-1)+tabs.length)%tabs.length;activate(tabs[target],true)}})});
const toast=document.querySelector('#toast');let timer;
function message(text){toast.textContent=text;toast.classList.add('show');clearTimeout(timer);timer=setTimeout(()=>toast.classList.remove('show'),3500)}
document.querySelector('#copy-hash').addEventListener('click',async()=>{try{await navigator.clipboard.writeText(document.querySelector('#checksum').textContent.trim());message('SHA-256 скопирована')}catch{message('Выдели контрольную сумму и скопируй вручную.')}});
