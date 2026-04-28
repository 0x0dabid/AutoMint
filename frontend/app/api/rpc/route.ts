import { NextRequest, NextResponse } from "next/server";

const UPSTREAM = process.env.RITUAL_RPC_URL ?? "https://rpc.ritualfoundation.org";

export async function POST(req: NextRequest) {
  const body = await req.text();
  const upstream = await fetch(UPSTREAM, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body,
  });
  const data = await upstream.json();
  return NextResponse.json(data, { status: upstream.status });
}
