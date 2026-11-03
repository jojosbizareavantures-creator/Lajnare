import {SessionProvider} from '@/components/Auth';
import {NavigationProvider} from '@/components/Navigation';
export const metadata={robots:{index:false,follow:false}};
export default function AccountLayout({children}:{children:React.ReactNode}){return <NavigationProvider><SessionProvider>{children}</SessionProvider></NavigationProvider>}
