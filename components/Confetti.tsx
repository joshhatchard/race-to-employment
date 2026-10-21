'use client';
import confetti from 'canvas-confetti';
export function celebrate(big=false){ if(typeof window==='undefined'||window.matchMedia('(prefers-reduced-motion: reduce)').matches)return; confetti({particleCount:big?180:65,spread:big?110:65,origin:{y:.65},colors:['#ffdf36','#ff4fa3','#3f8cff','#a9ed43']}); }
