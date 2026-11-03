import {AuthGate} from '@/components/Auth';
import {Provider} from '@/components/store';
import {AdminShell} from '@/components/AdminShell';
export const metadata={title:'Admin workspace · Evzon',robots:{index:false,follow:false}};
export default function AdminLayout({children}:{children:React.ReactNode}){return <AuthGate role="ADMIN"><Provider><AdminShell>{children}</AdminShell></Provider></AuthGate>}
