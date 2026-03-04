import "./globals.css";

import type { Metadata } from "next";
import { Manrope, Sora } from "next/font/google";

import { QueryProvider } from "@/components/query-provider";

const manrope = Manrope({
  subsets: ["latin"],
  variable: "--font-manrope",
  display: "swap",
});

const sora = Sora({
  subsets: ["latin"],
  variable: "--font-sora",
  display: "swap",
});

export const metadata: Metadata = {
  title: "Cattle Disease AI Dashboard",
  description: "Vet and system monitoring dashboard",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className={`${manrope.variable} ${sora.variable}`}>
        <QueryProvider>{children}</QueryProvider>
      </body>
    </html>
  );
}
