import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { Miniflare } from 'miniflare';

test('additive migration preserves populated legacy account, passkey, TOTP, backup and session records byte-for-byte',async()=>{
 const mf=new Miniflare({modules:true,script:'export default {fetch(){return new Response("test")}}',d1Databases:['DB']});try{
 const db=await mf.getD1Database('DB');
 const migrate=async(name:string)=>db.exec((await readFile(new URL('../migrations/'+name,import.meta.url),'utf8')).replace(/\n/g,' '));
 await migrate('0001_accounts.sql');
 await db.batch([
 db.prepare('INSERT INTO users VALUES(?,?,?,?,?,?)').bind('legacy-test','tester','encrypted-test-totp',123,7,100),
 db.prepare('INSERT INTO credentials VALUES(?,?,?,?)').bind('credential-test','legacy-test','public-test-key',3),
 db.prepare('INSERT INTO sessions VALUES(?,?,?,?,?)').bind('session-hash','legacy-test',7,100,10000),
 db.prepare('INSERT INTO backup_codes VALUES(?,?)').bind('backup-hash','legacy-test'),
 db.prepare('INSERT INTO pending VALUES(?,?,?,?,?,?)').bind('pending-hash','legacy-test','mfa','test-payload',10000,2)
 ]);
 const tables=['users','credentials','sessions','backup_codes','pending'];
 const before:{results:unknown[]}[]=await Promise.all(tables.map(table=>db.prepare(`SELECT * FROM ${table}`).all()));
 await migrate('0002_native_accounts.sql');
 const after:{results:unknown[]}[]=await Promise.all(tables.map(table=>db.prepare(`SELECT * FROM ${table}`).all()));
 assert.deepEqual(after.map(v=>v.results),before.map(v=>v.results));
 assert.equal((await db.prepare('SELECT COUNT(*) AS n FROM native_devices').first<{n:number}>())?.n,0);
 }finally{await mf.dispose();}
});
