"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useAccount, useConnect, useDisconnect } from "wagmi";
import { injected } from "wagmi/connectors";
import { shortenAddress } from "@/lib/utils";
import { cn } from "@/lib/utils";

export function NavBar() {
  const pathname = usePathname();
  const { address, isConnected } = useAccount();
  const { connect } = useConnect();
  const { disconnect } = useDisconnect();

  const links = [
    { href: "/", label: "Dashboard" },
    { href: "/create", label: "Create Agent" },
    { href: "/gallery", label: "NFT Gallery" },
  ];

  return (
    <nav className="border-b border-green-900/40 bg-black/80 backdrop-blur-sm sticky top-0 z-50">
      <div className="max-w-7xl mx-auto px-4 flex items-center justify-between h-14">
        {/* Logo */}
        <Link href="/" className="font-mono text-green-400 font-bold tracking-widest text-sm uppercase">
          ▶ AutoMint
        </Link>

        {/* Nav links */}
        <div className="flex items-center gap-6">
          {links.map(({ href, label }) => (
            <Link
              key={href}
              href={href}
              className={cn(
                "font-mono text-xs uppercase tracking-widest transition-colors",
                pathname === href ? "text-green-400" : "text-gray-500 hover:text-green-400"
              )}
            >
              {label}
            </Link>
          ))}
        </div>

        {/* Wallet */}
        <div>
          {isConnected && address ? (
            <button
              onClick={() => disconnect()}
              className="font-mono text-xs text-gray-400 hover:text-red-400 border border-gray-700 hover:border-red-700 px-3 py-1.5 transition-colors"
            >
              {shortenAddress(address)} ✕
            </button>
          ) : (
            <button
              onClick={() => connect({ connector: injected() })}
              className="font-mono text-xs text-green-400 border border-green-700 hover:border-green-400 px-3 py-1.5 transition-colors"
            >
              Connect Wallet
            </button>
          )}
        </div>
      </div>
    </nav>
  );
}
