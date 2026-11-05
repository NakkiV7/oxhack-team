import { startRegistration, startAuthentication } from '@simplewebauthn/browser';
import qrcode from 'qrcode-generator';
import { z } from 'zod';
const transport = z.enum(['usb','nfc','ble','internal','hybrid','smart-card','cable']);
const descriptor = z.object({ id: z.string(), type: z.literal('public-key'), transports: z.array(transport).optional() });
const registrationOptions = z.object({ challenge: z.string(), rp: z.object({ id: z.string().optional(), name: z.string() }), user: z.object({ id: z.string(), name: z.string(), displayName: z.string() }), pubKeyCredParams: z.array(z.object({ alg: z.number(), type: z.literal('public-key') })), timeout: z.number().optional(), attestation: z.enum(['none','direct','indirect','enterprise']).optional(), excludeCredentials: z.array(descriptor).optional(), authenticatorSelection: z.object({ residentKey: z.enum(['required','preferred','discouraged']).optional(), requireResidentKey: z.boolean().optional(), userVerification: z.enum(['required','preferred','discouraged']).optional(), authenticatorAttachment: z.enum(['platform','cross-platform']).optional() }).optional() });
const authenticationOptions = z.object({ challenge: z.string(), rpId: z.string().optional(), timeout: z.number().optional(), allowCredentials: z.array(descriptor).optional(), userVerification: z.enum(['required','preferred','discouraged']).optional() });
const content = document.querySelector<HTMLElement>('#account-content');
const status = document.querySelector<HTMLElement>('#account-status');
if (!content || !status) throw new Error('Account page is unavailable');
const panel = content, notice = status;
let csrf = '', busy = false, qrURL: string | null = null;
function element<K extends keyof HTMLElementTagNameMap>(tag: K, text?: string): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag); if (text) node.textContent = text; return node;
}
function say(text: string, error = false): void { notice.textContent = text; notice.dataset['error'] = String(error); }
function heading(title: string, description: string): void {
  if (qrURL) { URL.revokeObjectURL(qrURL); qrURL = null; }
  panel.replaceChildren(); const h = element('h2', title); h.tabIndex = -1;
  panel.append(h, element('p', description)); h.focus();
}
async function run(action: () => Promise<void>): Promise<void> {
  if (busy) return; busy = true; panel.setAttribute('aria-busy','true');
  try { say('Working…'); await action(); }
  catch (error) {
    if (error instanceof Error && error.name === 'NotAllowedError') say('Passkey sign-in was cancelled. Your account has not changed.', true);
    else say(error instanceof Error ? error.message : 'Something went wrong. Please try again.', true);
  } finally { busy = false; panel.removeAttribute('aria-busy'); }
}
function button(title: string, action: () => Promise<void>, secondary = false): HTMLButtonElement {
  const node = element('button',title); node.type='button'; node.className='button'+(secondary?' secondary':'');
  node.addEventListener('click', () => { void run(action); }); return node;
}
async function api(path: string, body?: unknown): Promise<Record<string, unknown>> {
  const headers: Record<string,string> = {};
  if (body !== undefined) headers['Content-Type']='application/json';
  if (csrf) headers['X-Spottr-CSRF']=csrf;
  const response = await fetch(path, { method:body===undefined?'GET':'POST', credentials:'same-origin', headers, body:body===undefined?undefined:JSON.stringify(body), cache:'no-store' });
  const value = z.record(z.string(),z.unknown()).parse(await response.json());
  if (!response.ok) {
    if (response.status===401 && csrf) { csrf=''; welcome(); throw new Error('Please sign in again before changing security settings.'); }
    throw new Error(typeof value['error']==='string'?value['error']:'The account service is unavailable.');
  }
  if (typeof value['csrf']==='string') csrf=value['csrf'];
  return value;
}
function input(label: string, name: string, options: { code?:boolean; backup?:boolean } = {}): { label: HTMLLabelElement; input: HTMLInputElement } {
  const field = element('input'); field.id=name; field.name=name; field.required=true;
  const title=element('label',label); title.htmlFor=name;
  if(options.code){field.inputMode='numeric';field.pattern='[0-9]{6}';field.maxLength=6;field.autocomplete='one-time-code';field.className='code-input';}
  if(options.backup){field.autocomplete='off';field.spellcheck=false;field.maxLength=64;}
  return {label:title,input:field};
}
function formSubmit(form: HTMLFormElement, title: string, action: () => Promise<void>): void {
  const submit=element('button',title);submit.type='submit';submit.className='button';form.append(submit);
  form.addEventListener('submit', event => { event.preventDefault();void run(action); });panel.append(form);
}
function welcome(): void {
  heading('Your account, securely','Sign in with your saved passkey, then enter a code from your Authenticator. There is no password or email sign-in.');
  panel.append(button('Sign in with a passkey',login));
  panel.append(button('Create an account',async()=>registration(),true));
  panel.append(element('p','You need a device or password manager that supports passkeys. Keep a synced passkey and your backup codes safe. Backup codes replace the Authenticator factor; they cannot replace a lost passkey.'));
  say('Choose how to continue.');
}
function registration(): void {
  heading('Make it yours','Choose a username. Use a name you are comfortable storing here; your email is not required.');
  const form=element('form'), name=input('Username','username');
  name.input.autocomplete='username';name.input.minLength=3;name.input.maxLength=32;name.input.pattern='[a-z0-9][a-z0-9_-]{2,31}';name.input.autocapitalize='none';
  form.append(name.label,name.input,element('p','Use 3–32 lowercase letters, numbers, underscores or dashes.'));
  const agreement=element('p');
  const terms=element('a','Terms'),privacy=element('a','Privacy notice');
  terms.href='/terms/';privacy.href='/privacy/';
  agreement.append('By creating an account, you agree to the ',terms,' and acknowledge the ',privacy,'.');
  form.append(agreement);
  formSubmit(form,'Create a passkey',async()=>{
    const start=await api('/api/auth/register/options',{username:name.input.value});
    const credential=await startRegistration({optionsJSON:registrationOptions.parse(start['options'])});
    const setup=await api('/api/auth/register/verify',{credential});authenticator(setup,false);
  });
  panel.append(button('Back to sign in',async()=>welcome(),true));say('First create a passkey, then connect your Authenticator.');
}
async function login(): Promise<void> {
  const start=await api('/api/auth/login/options',{});
  const credential=await startAuthentication({optionsJSON:authenticationOptions.parse(start['options'])});
  await api('/api/auth/login/verify',{credential});secondFactor(false);
}
function secondFactor(backup: boolean): void {
  heading(backup?'Use a backup code':'Your second factor',backup?'Enter one unused backup code. It will be spent once this sign-in succeeds.':'Open your Authenticator and enter its current six-digit Spottr code.');
  const form=element('form'), code=input(backup?'Backup code':'Authenticator code','second-factor',{code:!backup,backup});form.append(code.label,code.input);
  formSubmit(form,'Finish signing in',async()=>{
    const result=await api('/api/auth/mfa',backup?{backupCode:code.input.value}:{code:code.input.value});
    await dashboard();if(result['usedBackupCode']===true)say('Signed in with a backup code. Consider replacing your Authenticator now.');
  });
  panel.append(button(backup?'Use my Authenticator instead':'Use a backup code',async()=>secondFactor(!backup),true));
  say('Your passkey was verified. Complete the second factor to sign in.');code.input.focus();
}
function authenticator(value: Record<string,unknown>, replacement: boolean): void {
  const secret=z.string().parse(value['secret']),uri=z.string().startsWith('otpauth://').parse(value['uri']);
  heading(replacement?'Connect a new Authenticator':'Add Spottr to your Authenticator','Scan this QR code in your Authenticator app, or enter the setup key manually. The QR code is generated in this browser.');
  const qr=qrcode(0,'M');qr.addData(uri);qr.make();
  const svg=qr.createSvgTag({scalable:true,margin:2});qrURL=URL.createObjectURL(new Blob([svg],{type:'image/svg+xml'}));
  const image=element('img');image.src=qrURL;image.alt='Spottr Authenticator setup QR code';image.className='qr';panel.append(image);
  const key=element('p',secret);key.className='seed';panel.append(key,button('Copy setup key',async()=>{await navigator.clipboard.writeText(secret);say('Setup key copied. Keep it private.');},true));
  const form=element('form'),code=input('Current Authenticator code','setup-code',{code:true});form.append(code.label,code.input);
  formSubmit(form,'Verify Authenticator',async()=>{
    const result=await api(replacement?'/api/account/authenticator/verify':'/api/auth/enroll',{code:code.input.value});
    backups(z.array(z.string()).length(10).parse(result['backupCodes']));
  });
  say('Setup expires in five minutes. Never share the QR code or setup key.');
}
function download(filename: string, value: string, type = 'text/plain'): void {
  const url=URL.createObjectURL(new Blob([value],{type})),anchor=element('a');anchor.href=url;anchor.download=filename;anchor.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
}
function backups(codes: string[]): void {
  heading('Save your backup codes','Each code can replace your Authenticator once, together with your passkey. These codes are shown only now. Save them somewhere private.');
  const list=element('ul');list.className='backup-list';for(const code of codes)list.append(element('li',code));panel.append(list);
  panel.append(button('Download backup codes',async()=>{download('spottr-backup-codes.txt','Spottr single-use backup codes\nKeep these private. A passkey is still required.\n\n'+codes.join('\n')+'\n');say('Backup-code download prepared on this device.');},true));
  const confirm=element('label'),check=element('input');check.type='checkbox';confirm.className='save-confirm';confirm.append(check,element('span','I saved these codes somewhere private.'));
  const done=button('Continue to my account',dashboard);done.disabled=true;check.addEventListener('change',()=>{done.disabled=!check.checked;});panel.append(confirm,done);say('Your two-factor setup is complete. Save the recovery codes before continuing.');
}
async function dashboard(): Promise<void> {
  const session=await api('/api/auth/session');
  heading('Welcome, '+z.string().parse(session['username']),'Your website account is protected by a passkey and Authenticator. Every new sign-in needs both factors.');
  const summary=element('div');summary.className='security-row';summary.append(element('h3','Recovery codes'),element('p',String(z.number().parse(session['backupCodesRemaining']))+' unused backup codes remain. New codes invalidate the old set.'));
  summary.append(button('Create new backup codes',async()=>backups(z.array(z.string()).length(10).parse((await api('/api/account/backup-codes',{}))['backupCodes'])),true));panel.append(summary);
  const mfa=element('div');mfa.className='security-row';mfa.append(element('h3','Authenticator'),element('p','To replace a lost or changed Authenticator, sign in with a backup code first. Verify the new setup before the old one is replaced.'));
  mfa.append(button('Replace Authenticator',async()=>authenticator(await api('/api/account/authenticator/options',{}),true),true));panel.append(mfa);
  const data=element('div');data.className='security-row';data.append(element('h3','Your account data'),element('p','The website stores sign-in information. It does not hold your workouts, videos or health readings.'));
  data.append(button('Download account data',async()=>download('spottr-account.json',JSON.stringify(await api('/api/account/export'),null,2),'application/json'),true));panel.append(data);
  const deletion=element('div');deletion.id='delete';deletion.className='security-row';deletion.append(element('h3','Delete this website account'),element('p','This removes your sign-in record and revokes its sessions. Local iPhone history and Apple purchases remain separate.'));
  deletion.append(button('Delete account',async()=>deleteAccount(),true));panel.append(deletion,button('Sign out',async()=>{await api('/api/auth/logout',{});csrf='';welcome();},true));say('Signed in. Security changes require sign-in within the last five minutes.');
}
function deleteAccount(): void {
  heading('Delete your website account?','This permanently removes your username, passkey public key, encrypted Authenticator record, backup-code hashes and sessions from the active account database. It does not cancel an Apple subscription or delete local phone data.');
  const form=element('form'),confirmation=input('Type DELETE to confirm','delete-confirm');confirmation.input.autocomplete='off';confirmation.input.pattern='DELETE';form.append(confirmation.label,confirmation.input);
  formSubmit(form,'Delete my website account',async()=>{await api('/api/account/delete',{confirm:confirmation.input.value});csrf='';welcome();say('Your website account was deleted. Local phone data and Apple purchases were unchanged.');});
  panel.append(button('Keep my account',dashboard,true));say('You can cancel and keep your account.');
}
void run(async()=>{
  try { await dashboard(); }
  catch { csrf='';welcome(); }
});
