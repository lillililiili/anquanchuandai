import test from 'node:test';
import assert from 'node:assert/strict';
import { authFetch, captureAuthRequest, clearAuth, onAuthCleared, saveAuth } from '../src/lib/auth.js';

test('logout removes saved auth but an existing call cleanup uses only its original temporary auth closure', async () => {
  const originalStorage = globalThis.sessionStorage, originalFetch = globalThis.fetch;
  const values = new Map(), requests = [], cleanups = [];
  globalThis.sessionStorage = { getItem:key => values.get(key) ?? null, setItem:(key,value) => values.set(key,value), removeItem:key => values.delete(key) };
  globalThis.fetch = async (url, options) => { requests.push({url, token:options.headers['X-Wearable-Token']}); return {status:200}; };
  const unsubscribe = onAuthCleared(value => cleanups.push(value));
  try {
    saveAuth('test-original-token','original-account');
    const originalRequest = captureAuthRequest();
    clearAuth();
    assert.equal(values.size, 0); assert.equal(cleanups.length, 1); assert.deepEqual(Object.keys(cleanups[0]), ['request']);
    saveAuth('test-new-token','new-account');
    await originalRequest('/original/end', { headers:{'X-Wearable-Token':'unexpected-new-token'} });
    await cleanups[0].request('/same-original/end');
    assert.deepEqual(requests.map(row => row.token), ['test-original-token','test-original-token']);
    assert.equal(values.get('wearable-guardian-token'),'test-new-token');
    assert.equal(JSON.stringify(cleanups).includes('test-original-token'), false);
  } finally { unsubscribe(); globalThis.sessionStorage=originalStorage; globalThis.fetch=originalFetch; }
});

test('a 401 triggers synchronous local auth listeners and logout even when cleanup rejects', async () => {
  const originalStorage=globalThis.sessionStorage, originalFetch=globalThis.fetch, originalWindow=globalThis.window;
  const values=new Map([['wearable-guardian-token','test-expired-token'],['rolling-session','old']]); let detached=false;
  globalThis.sessionStorage={getItem:key=>values.get(key)??null,removeItem:key=>values.delete(key)};
  globalThis.window={location:{hash:'#/dispatch'}};
  globalThis.fetch=async()=>({status:401});
  const unsubscribe=onAuthCleared(()=>{detached=true;return Promise.reject(Error('cleanup unavailable'));});
  try {
    await authFetch('/expired');
    assert.equal(detached,true); assert.equal(values.size,0); assert.equal(window.location.hash,'/login');
    await new Promise(resolve=>setImmediate(resolve));
  } finally { unsubscribe();globalThis.sessionStorage=originalStorage;globalThis.fetch=originalFetch;globalThis.window=originalWindow; }
});

test('a late 401 from the previous account cannot clear a newly authenticated session', async () => {
  const originalStorage=globalThis.sessionStorage, originalFetch=globalThis.fetch, originalWindow=globalThis.window;
  const values=new Map(); const requests=[]; let cleanups=0;
  globalThis.sessionStorage={getItem:key=>values.get(key)??null,setItem:(key,value)=>values.set(key,value),removeItem:key=>values.delete(key)};
  globalThis.window={location:{hash:'#/overview'}};
  globalThis.fetch=(url,options)=>new Promise(resolve=>requests.push({url,token:options.headers['X-Wearable-Token'],resolve}));
  const unsubscribe=onAuthCleared(()=>{cleanups++;});
  try {
    saveAuth('previous-token','previous-account');
    const previous=authFetch('/previous/snapshot');
    saveAuth('current-token','current-account');
    const current=authFetch('/current/snapshot');
    requests[0].resolve({status:401});
    assert.equal((await previous).status,401,'the caller still receives its failed response');
    assert.equal(values.get('wearable-guardian-token'),'current-token');
    assert.equal(values.get('rolling-session'),'current-account');
    assert.equal(window.location.hash,'#/overview');
    assert.equal(cleanups,0,'old requests must not terminate the new account call or media session');
    requests[1].resolve({status:200}); await current;
    assert.deepEqual(requests.map(request=>request.token),['previous-token','current-token']);
  } finally { unsubscribe();globalThis.sessionStorage=originalStorage;globalThis.fetch=originalFetch;globalThis.window=originalWindow; }
});

test('a pending anonymous request cannot invalidate a login completed before its 401 arrives', async () => {
  const originalStorage=globalThis.sessionStorage, originalFetch=globalThis.fetch, originalWindow=globalThis.window;
  const values=new Map(); let finish;
  globalThis.sessionStorage={getItem:key=>values.get(key)??null,setItem:(key,value)=>values.set(key,value),removeItem:key=>values.delete(key)};
  globalThis.window={location:{hash:'#/overview'}};
  globalThis.fetch=()=>new Promise(resolve=>{finish=resolve;});
  try {
    const anonymous=authFetch('/pre-login/snapshot');
    saveAuth('current-token','current-account');
    finish({status:401}); await anonymous;
    assert.equal(values.get('wearable-guardian-token'),'current-token');
    assert.equal(window.location.hash,'#/overview');
  } finally { globalThis.sessionStorage=originalStorage;globalThis.fetch=originalFetch;globalThis.window=originalWindow; }
});
