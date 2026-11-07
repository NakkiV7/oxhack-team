import { NativeError, type Context } from './native-sessions.ts';
import { randomToken } from './crypto.ts';
import { AwsClient } from 'aws4fetch';
import { z } from 'zod';
const acceptance=z.object({MessageId:z.string().trim().min(1).max(200)});
export async function sendOwnershipCode(c:Context,email:string,code:string) {
 const {AWS_SES_ACCESS_KEY_ID:accessKeyId,AWS_SES_SECRET_ACCESS_KEY:secretAccessKey,AWS_SES_REGION:region,AWS_SES_FROM:sender,AWS_SES_CONFIGURATION_SET:configurationSet}=c.env;
 if(!accessKeyId?.trim() || !secretAccessKey?.trim() || region!=='eu-west-2' || sender!=='auth@mail.spottr.omarchoudhry.co.uk' || configurationSet!=='spottr-auth') throw new NativeError(503,'temporarily_unavailable');
 const date=new Date(c.now()).toISOString(),recipient=await c.hash('mail:'+email);
 const sent=await c.sql('INSERT INTO native_mail_reservations(id,day,month,recipient,created_at) SELECT ?,?,?,?,? WHERE (SELECT COUNT(*) FROM native_mail_reservations WHERE day=?)<100 AND (SELECT COUNT(*) FROM native_mail_reservations WHERE month=?)<3000 AND (SELECT COUNT(*) FROM native_mail_reservations WHERE recipient=? AND created_at>?)<3',randomToken(),date.slice(0,10),date.slice(0,7),recipient,c.now(),date.slice(0,10),date.slice(0,7),recipient,c.now()-3600000).run();
 if(sent.meta.changes!==1) throw new NativeError(503,'temporarily_unavailable');
 try {
  const client=new AwsClient({accessKeyId,secretAccessKey,sessionToken:c.env.AWS_SES_SESSION_TOKEN,region,service:'ses',retries:0});
  const request=await client.sign('https://email.eu-west-2.amazonaws.com/v2/email/outbound-emails',{
   method:'POST',redirect:'error',signal:AbortSignal.timeout(10000),headers:{'Content-Type':'application/json'},
   body:JSON.stringify({FromEmailAddress:sender,Destination:{ToAddresses:[email]},ConfigurationSetName:configurationSet,Content:{Simple:{Subject:{Charset:'UTF-8',Data:'Your Spottr verification code'},Body:{Text:{Charset:'UTF-8',Data:`Your Spottr verification code is ${code}. It expires in five minutes. If you did not request this, ignore this email.`}}}}})
  });
  const response=await c.fetch(request);
  if(response.status!==200 || response.redirected) {await response.body?.cancel();throw new NativeError(503,'temporarily_unavailable');}
  const reader=response.body?.getReader();if(!reader) throw new NativeError(503,'temporarily_unavailable');
  const bytes=new Uint8Array(1024);let size=0;
  while(true) {
   const next=await reader.read();if(next.done) break;
   if(size+next.value.byteLength>bytes.length) {await reader.cancel();throw new NativeError(503,'temporarily_unavailable');}
   bytes.set(next.value,size);size+=next.value.byteLength;
  }
  acceptance.parse(JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes.subarray(0,size))));
 } catch {throw new NativeError(503,'temporarily_unavailable');}
}
