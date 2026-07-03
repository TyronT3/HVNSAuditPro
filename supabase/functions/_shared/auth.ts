import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export type CallerProfile = {
  id: string;
  email: string;
  role: string;
  active: boolean;
  greatsoft_emp_id?: string | null;
  greatsoft_sync_enabled?: boolean | null;
};

export const MANAGER_ROLES = ["manager", "director", "tyron"];

export function adminClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

export async function getCallerProfile(req: Request): Promise<
  { profile: CallerProfile; error?: never } | { profile?: never; error: { status: number; message: string } }
> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return { error: { status: 401, message: "Missing Authorization header" } };

  const userClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: authData, error: authError } = await userClient.auth.getUser();
  if (authError || !authData.user) return { error: { status: 401, message: "Invalid user session" } };

  const { data: profile, error: profileError } = await adminClient()
    .from("users")
    .select("id,email,role,active,greatsoft_emp_id,greatsoft_sync_enabled")
    .eq("id", authData.user.id)
    .single();

  if (profileError || !profile || !profile.active) {
    return { error: { status: 403, message: "Active user profile not found" } };
  }

  return { profile: profile as CallerProfile };
}
