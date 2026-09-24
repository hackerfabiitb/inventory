export const dynamic = "force-dynamic";
import { getSession } from "@/lib/session";
import StockClient from "./StockClient";

export default async function StockPage() {
  const session = await getSession();
  return <StockClient userName={session?.name ?? ""} />;
}
