import {readFile} from 'node:fs/promises';
import {stripTypeScriptTypes} from 'node:module';
export async function resolve(spec,ctx,next){try{return await next(spec,ctx)}catch(e){if(spec.startsWith('.')&&!spec.endsWith('.ts')) return next(spec.replace(/\.js$/,'')+'.ts',ctx);throw e}}
export async function load(url,ctx,next){if(url.endsWith('.json'))return {format:'module',source:'export default '+await readFile(new URL(url),'utf8'),shortCircuit:true};if(url.endsWith('.ts'))return {format:'module',source:stripTypeScriptTypes(await readFile(new URL(url),'utf8'),{mode:'transform'}),shortCircuit:true};return next(url,ctx)}
