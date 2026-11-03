import {AuthGate} from '@/components/Auth';
import {ReferrerPortal} from '@/components/ReferrerPortal';
export const metadata={title:'Partner portal · Evzon',robots:{index:false,follow:false}};
export default function ReferrerLayout({children}:{children:React.ReactNode}){return <AuthGate role="REFERRER"><ReferrerPortal/>{children}</AuthGate>}
