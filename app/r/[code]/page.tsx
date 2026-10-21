import type {Metadata} from 'next';
import {RaceLinkRedirect} from '@/components/RaceLinkRedirect';
import {normaliseRaceCode} from '@/lib/race-link';

type Props={params:Promise<{code:string}>};

export async function generateMetadata({params}:Props):Promise<Metadata> {
  const {code:rawCode}=await params;
  const code=normaliseRaceCode(rawCode) || 'RACE';
  const title=`Join ${code} on Breads Up!`;
  const description=`Join my Breads Up! job-hunt race. Your invite code is ${code}.`;
  return {
    title,
    description,
    alternates:{canonical:`/r/${code}`},
    openGraph:{type:'website',siteName:'Breads Up!',title,description,url:`/r/${code}`,images:[{url:`/r/${code}/opengraph-image`,width:1200,height:630,alt:`Breads Up! invite code ${code}`}]},
    twitter:{card:'summary_large_image',title,description,images:[`/r/${code}/opengraph-image`]},
  };
}

export default async function RaceInvitePage({params}:Props) {
  const {code:rawCode}=await params;
  const code=normaliseRaceCode(rawCode);
  return code ? <RaceLinkRedirect code={code}/> : <main className="center"><h1>That race link is invalid.</h1></main>;
}
