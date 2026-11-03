import {MarketingShell} from '@/components/marketing/MarketingShell';
export const metadata={title:'Candidate application · Evzon',robots:{index:false,follow:false}};
export default function Layout({children}:{children:React.ReactNode}){return <MarketingShell>{children}</MarketingShell>}
