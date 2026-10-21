import {ImageResponse} from 'next/og';
import {normaliseRaceCode} from '@/lib/race-link';

export const runtime='edge';
export const size={width:1200,height:630};
export const contentType='image/png';

export default async function OpenGraphImage({params}:{params:Promise<{code:string}>}) {
  const {code:rawCode}=await params;
  const code=normaliseRaceCode(rawCode) || 'RACE';
  return new ImageResponse(
    <div style={{background:'#5B3CDD',color:'#fff',display:'flex',height:'100%',width:'100%',fontFamily:'sans-serif',overflow:'hidden',padding:'70px 82px',position:'relative'}}>
      <div style={{background:'#6A4DE8',borderRadius:'50%',height:620,width:620,position:'absolute',right:-185,top:-245}}/>
      <div style={{display:'flex',flexDirection:'column',justifyContent:'space-between',position:'relative',width:'100%'}}>
        <div style={{fontSize:56,fontWeight:800,letterSpacing:-3}}>breads <span style={{color:'#FF9BCB'}}>up!</span></div>
        <div style={{display:'flex',flexDirection:'column'}}>
          <div style={{fontSize:38,fontWeight:700,letterSpacing:5}}>YOU’RE INVITED TO RACE</div>
          <div style={{color:'#FF9BCB',fontSize:112,fontWeight:800,letterSpacing:4,lineHeight:1.05,marginTop:18}}>{code}</div>
        </div>
        <div style={{fontSize:30,fontWeight:600}}>Race your friends to employment.</div>
      </div>
    </div>,
    size,
  );
}
