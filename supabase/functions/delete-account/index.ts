import { createClient } from 'npm:@supabase/supabase-js@2';

const jsonHeaders = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: jsonHeaders });
  }
  if (request.method !== 'POST') {
    return new Response(
      JSON.stringify({ error: 'Method not allowed' }),
      { status: 405, headers: jsonHeaders },
    );
  }

  const authorization = request.headers.get('Authorization');
  if (!authorization?.startsWith('Bearer ')) {
    return new Response(
      JSON.stringify({ error: 'Missing authorization' }),
      { status: 401, headers: jsonHeaders },
    );
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceRoleKey) {
    return new Response(
      JSON.stringify({ error: 'Server configuration is incomplete' }),
      { status: 500, headers: jsonHeaders },
    );
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const token = authorization.substring('Bearer '.length);
  const { data, error: userError } = await admin.auth.getUser(token);
  if (userError || !data.user) {
    return new Response(
      JSON.stringify({ error: 'Invalid session' }),
      { status: 401, headers: jsonHeaders },
    );
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(
    data.user.id,
  );
  if (deleteError) {
    return new Response(
      JSON.stringify({ error: 'Could not delete account' }),
      { status: 500, headers: jsonHeaders },
    );
  }

  return new Response(
    JSON.stringify({ deleted: true }),
    { status: 200, headers: jsonHeaders },
  );
});
