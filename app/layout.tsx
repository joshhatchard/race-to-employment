import type { Metadata, Viewport } from 'next';
import { Poppins } from 'next/font/google';
import './globals.css';
import './duolingo-ui.css';
import './countdown-lobby.css';
import './profile-avatars.css';
import './share-button.css';
import './ready-indicator.css';
import './brand.css';
import './responsive.css';
import {publicSiteUrl} from '@/lib/race-link';
const poppins=Poppins({subsets:['latin'],weight:['500','600','700','800'],variable:'--font-poppins',display:'swap'});
export const metadata: Metadata = {metadataBase:new URL(publicSiteUrl),title:'Breads Up!',description:'Race your friends to your next job.',manifest:'/manifest.webmanifest',icons:{icon:[{url:'/favicon.svg',type:'image/svg+xml'},{url:'/icon-32.png',sizes:'32x32',type:'image/png'}],apple:'/apple-touch-icon.png'},appleWebApp:{capable:true,statusBarStyle:'black-translucent',title:'Breads Up!'}};
export const viewport: Viewport = {themeColor:'#5B3CDD',width:'device-width',initialScale:1};
export default function RootLayout({children}:{children:React.ReactNode}) { return <html lang="en"><body className={poppins.variable}>{children}</body></html> }
