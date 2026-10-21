'use client';

import {useEffect} from 'react';

export function RaceLinkRedirect({code}:{code:string}) {
  useEffect(()=>{
    window.location.replace(`/?race=${encodeURIComponent(code)}`);
  },[code]);

  return <main className="center"><div className="spinner"/><p>Opening your race…</p><a href={`/?race=${encodeURIComponent(code)}`}>Continue to Breads Up!</a></main>;
}
