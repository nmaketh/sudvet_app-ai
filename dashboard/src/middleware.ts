import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

const PROTECTED_PREFIXES = [
  "/overview",
  "/cases",
  "/triage",
  "/analytics",
  "/users",
  "/system",
  "/settings",
  "/animals",
];

export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;
  const isProtected = PROTECTED_PREFIXES.some(
    (prefix) => pathname === prefix || pathname.startsWith(`${prefix}/`)
  );

  if (isProtected) {
    const session = request.cookies.get("cattle-session");
    if (!session?.value) {
      const loginUrl = new URL("/login", request.url);
      loginUrl.searchParams.set("next", pathname);
      return NextResponse.redirect(loginUrl);
    }
  }

  return NextResponse.next();
}

export const config = {
  matcher: [
    /*
     * Match all paths except:
     * - _next/static / _next/image (Next.js internals)
     * - favicon.ico
     * - /api routes (handled separately)
     * - /login (auth page)
     */
    "/((?!_next/static|_next/image|favicon.ico|api/|login).*)",
  ],
};
