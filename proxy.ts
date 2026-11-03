import {NextRequest,NextResponse} from 'next/server';
import {secureResponse} from '@/lib/response-security';

// Authorization stays in the server API and Supabase; this adds response headers.
export function proxy(request:NextRequest){
 return secureResponse(request,NextResponse.next());
}

export const config={matcher:['/((?!_next/static|_next/image|favicon.svg).*)']};
