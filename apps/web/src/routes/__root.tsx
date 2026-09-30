/// <reference types="vite/client" />
import * as stylex from "@stylexjs/stylex";
import { type QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { createRootRouteWithContext, HeadContent, Outlet, Scripts } from "@tanstack/react-router";
import type { ReactNode } from "react";
import { copy } from "@cauldron/shared";
import { ThemeToggle } from "../components/ThemeToggle";
import { themeScript } from "../lib/theme";
import appCss from "../styles/app.css?url";
import { chrome, colors, fonts, type } from "../styles/tokens.stylex";

export const Route = createRootRouteWithContext<{ queryClient: QueryClient }>()({
  head: () => ({
    meta: [
      { charSet: "utf-8" },
      { name: "viewport", content: "width=device-width, initial-scale=1" },
      { title: copy.ui.appName.text },
      // The router keeps one meta per name, so the browser chrome uses Mocha, the default theme.
      { name: "theme-color", content: chrome.mocha },
    ],
    links: [
      { rel: "stylesheet", href: appCss },
      { rel: "icon", href: "/favicon.ico", sizes: "32x32" },
      { rel: "icon", href: "/favicon.svg", type: "image/svg+xml" },
      { rel: "apple-touch-icon", href: "/apple-touch-icon.png" },
      { rel: "manifest", href: "/manifest.webmanifest" },
      ...(import.meta.env.DEV ? [{ rel: "stylesheet", href: "/virtual:stylex.css" }] : []),
    ],
    scripts: [{ children: themeScript }],
  }),
  component: RootComponent,
});

function RootComponent() {
  const { queryClient } = Route.useRouteContext();
  return (
    <RootDocument>
      <QueryClientProvider client={queryClient}>
        <Outlet />
      </QueryClientProvider>
    </RootDocument>
  );
}

function RootDocument({ children }: { children: ReactNode }) {
  return (
    // The pre-paint script may set data-theme before React hydrates.
    <html lang="en" suppressHydrationWarning>
      <head>
        <HeadContent />
      </head>
      <body {...stylex.props(styles.body)}>
        <div {...stylex.props(styles.toggle)}>
          <ThemeToggle />
        </div>
        {children}
        <Scripts />
      </body>
    </html>
  );
}

const styles = stylex.create({
  body: {
    margin: 0,
    minHeight: "100vh",
    backgroundColor: colors.base,
    color: colors.ink,
    fontFamily: fonts.ui,
    fontSize: type.bodySize,
    lineHeight: type.bodyLeading,
    WebkitFontSmoothing: "antialiased",
  },
  toggle: { position: "fixed", top: 12, right: 12 },
});
