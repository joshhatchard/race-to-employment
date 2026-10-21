import { createClient } from '@supabase/supabase-js';
const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
// Supabase projects created with the newer dashboard expose a publishable key;
// older projects use an anon key. Both are safe browser keys and interchangeable here.
const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
export const supabase = url && key ? createClient(url, key, { auth:{flowType:'pkce',persistSession:true,autoRefreshToken:true,detectSessionInUrl:false} }) : null;
export const raceCode = process.env.NEXT_PUBLIC_RACE_CODE || 'RACE24';
export const colours = ['#ff4fa3','#ffdf36','#3f8cff','#a9ed43','#ff9138','#a56cff','#22d9e8','#ff5757','#53e3b1','#e84ee5'];
export type Player={user_id:string;display_name:string;colour:string;avatar:string;ready:boolean;status:string;hired_at:string|null;hired_rank:number|null;hired_company:string|null;applications:number;interviews:number;offers:number;rejections:number;current_streak:number;longest_streak:number;last_applied_on:string|null};
export type Application={id:string;company_name:string;role:string|null;url:string|null;note:string|null;source:string;status:string;created_at:string;deleted_at:string|null};
export type FeedItem={id:string;kind:string;user_id:string;display_name:string;colour:string;company:string|null;role:string|null;stage:string|null;batch_id:string|null;happened_at:string;removed:boolean};
export function message(error:unknown){
  if (error instanceof Error) return error.message;
  if (typeof error === 'object' && error !== null && 'message' in error && typeof error.message === 'string') return error.message;
  return 'Something went wrong. Try again.';
}
