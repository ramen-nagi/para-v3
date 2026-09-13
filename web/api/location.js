module.exports = async function handler(request, response) {
  response.setHeader('Cache-Control', 'no-store');

  if (request.method !== 'GET') {
    return response.status(405).json({ error: 'Method not allowed' });
  }

  const token = String(request.query.token || '');
  const uuidPattern =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  if (!uuidPattern.test(token)) {
    return response.status(400).json({ error: 'Invalid tracking link' });
  }

  const supabaseUrl = String(process.env.SUPABASE_URL || '').replace(/\/$/, '');
  const supabaseKey = process.env.SUPABASE_ANON_KEY;
  if (!supabaseUrl || !supabaseKey) {
    return response.status(500).json({ error: 'Tracker is not configured' });
  }

  try {
    const result = await fetch(
      `${supabaseUrl}/rest/v1/rpc/get_live_location`,
      {
        method: 'POST',
        headers: {
          apikey: supabaseKey,
          Authorization: `Bearer ${supabaseKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ share_token: token }),
      },
    );

    if (!result.ok) {
      return response.status(502).json({ error: 'Location service unavailable' });
    }
    return response.status(200).json(await result.json());
  } catch (_) {
    return response.status(502).json({ error: 'Location service unavailable' });
  }
};
