import { NativeError, type Context } from './native-sessions.ts';
import { randomToken } from './crypto.ts';
export async function sendOwnershipCode(c:Context,email:string,code:string) {
 if(!c.env.RESEND_API_KEY || !c.env.RESEND_FROM || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(c.env.RESEND_FROM)) throw new NativeError(503,'temporarily_unavailable');
 const date=new Date(c.now()).toISOString(),recipient=await c.hash('mail:'+email);
 const sent=await c.sql('INSERT INTO native_mail_reservations(id,day,month,recipient,created_at) SELECT ?,?,?,?,? WHERE (SELECT COUNT(*) FROM native_mail_reservations WHERE day=?)<100 AND (SELECT COUNT(*) FROM native_mail_reservations WHERE month=?)<3000 AND (SELECT COUNT(*) FROM native_mail_reservations WHERE recipient=? AND created_at>?)<3',randomToken(),date.slice(0,10),date.slice(0,7),recipient,c.now(),date.slice(0,10),date.slice(0,7),recipient,c.now()-3600000).run();
 if(sent.meta.changes!==1) throw new NativeError(503,'temporarily_unavailable');
 const response=await c.fetch('https://api.resend.com/emails',{method:'POST',headers:{Authorization:'Bearer '+c.env.RESEND_API_KEY,'Content-Type':'application/json'},body:JSON.stringify({from:c.env.RESEND_FROM,to:[email],subject:'Your Spottr verification code',text:`Your Spottr verification code is ${code}. It expires in five minutes. If you did not request this, ignore this email.`})});
 if(!response.ok) throw new NativeError(503,'temporarily_unavailable');
}
