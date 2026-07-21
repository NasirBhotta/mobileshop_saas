import { createClient } from 'jsr:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (request.method !== 'POST') {
    return json({ error: 'Method not allowed.' }, 405);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const authorization = request.headers.get('Authorization');
  if (!supabaseUrl || !anonKey || !serviceKey || !authorization) {
    return json({ error: 'Authentication configuration is missing.' }, 401);
  }

  const caller = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const service = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let invitationId: string | null = null;
  let invitedUserId: string | null = null;
  let stage = 'authenticate_caller';
  try {
    const { data: authData, error: authError } = await caller.auth.getUser();
    if (authError || !authData.user) {
      return json({ error: 'Authentication required.' }, 401);
    }

    stage = 'parse_request';
    const body = await request.json();
    const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
    const fullName = typeof body.fullName === 'string' ? body.fullName.trim() : '';
    const roleId = typeof body.roleId === 'string' ? body.roleId : '';

    stage = 'request_invitation';
    const { data: requestedId, error: requestError } = await caller.rpc(
      'request_staff_invitation',
      { p_email: email, p_full_name: fullName, p_role_id: roleId },
    );
    if (requestError) throw requestError;
    invitationId = requestedId as string;

    stage = 'invite_auth_user';
    const redirectTo = Deno.env.get('STAFF_INVITE_REDIRECT_URL') ??
      'io.supabase.mobileshop://login-callback/';
    const { data: inviteData, error: inviteError } =
      await service.auth.admin.inviteUserByEmail(email, {
        redirectTo,
        data: { full_name: fullName, staff_invitation_id: invitationId },
      });
    if (inviteError || !inviteData.user) {
      throw inviteError ?? new Error('Invitation user was not created.');
    }
    invitedUserId = inviteData.user.id;

    stage = 'complete_invitation';
    const { error: completeError } = await service.rpc(
      'complete_staff_invitation',
      { p_invitation_id: invitationId, p_user_id: invitedUserId },
    );
    if (completeError) throw completeError;

    return json({ invitationId, userId: invitedUserId }, 200);
  } catch (error) {
    if (invitedUserId != null) {
      await service.auth.admin.deleteUser(invitedUserId);
    }
    if (invitationId != null) {
      await service.rpc('fail_staff_invitation', {
        p_invitation_id: invitationId,
      });
    }
    const message = errorMessage(error);
    console.error(JSON.stringify({
      event: 'staff_invitation_failed',
      stage,
      invitationId,
      invitedUserId,
      message,
    }));
    return json({ error: message, stage }, 400);
  }
});

function errorMessage(error: unknown): string {
  if (error instanceof Error && error.message.trim().length > 0) {
    return error.message;
  }
  if (error != null && typeof error === 'object') {
    const value = error as Record<string, unknown>;
    for (const key of ['message', 'error_description', 'details', 'error']) {
      const candidate = value[key];
      if (typeof candidate === 'string' && candidate.trim().length > 0) {
        return candidate;
      }
    }
    try {
      return JSON.stringify(value);
    } catch (_) {
      // Fall through to the safe generic response.
    }
  }
  return 'Staff invitation failed.';
}

function json(body: Record<string, unknown>, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
