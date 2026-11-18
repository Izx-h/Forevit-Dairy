import type { Metadata, Viewport } from "next";
import { GeistMono } from "geist/font/mono";
import { GeistSans } from "geist/font/sans";
import "./globals.css";

export const metadata: Metadata = {
  title: {
    default: "Forevit Dairy | Research Workspace",
    template: "%s | Forevit Dairy"
  },
  description: "A traceable research and project workspace for Forevit Dairy.",
  manifest: "/manifest.webmanifest",
  icons: { icon: "/icon.svg", apple: "/icon.svg" },
  applicationName: "Forevit Dairy",
  appleWebApp: { capable: true, title: "Forevit Dairy", statusBarStyle: "default" }
};

export const viewport: Viewport = {
  themeColor: "#145447",
  width: "device-width",
  initialScale: 1
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className={`${GeistSans.variable} ${GeistMono.variable}`}>
      <body>{children}</body>
    </html>
  );
}
