// La Loge de Claire : donne des adresses d'envoi signées pour les photos de costumes.
// Réservé à l'Espace Claire : le jeton de session est vérifié dans la base.
const SB = Deno.env.get('SUPABASE_URL')!;
const SR = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'content-type, apikey, authorization, x-client-info', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const H = { apikey: SR, Authorization: `Bearer ${SR}`, 'Content-Type': 'application/json' };
const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { ...CORS, 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const { token, n } = await req.json();
    if (typeof token !== 'string' || token.length < 20) return json({ error: 'session' }, 401);
    const r = await fetch(`${SB}/rest/v1/loge_sessions?token=eq.${encodeURIComponent(token)}&expire=gt.${new Date().toISOString()}&select=token`, { headers: H });
    if (!(await r.json()).length) return json({ error: 'session' }, 401);
    const count = Math.max(1, Math.min(30, Number(n) || 1));
    const out = [];
    for (let i = 0; i < count; i++) {
      const id = crypto.randomUUID();
      const one: Record<string, string> = { path: `c/${id}.jpg` };
      for (const [k, p] of [['full', `c/${id}.jpg`], ['thumb', `c/${id}_t.jpg`]]) {
        const s = await fetch(`${SB}/storage/v1/object/upload/sign/loge-photos/${p}`, { method: 'POST', headers: H, body: '{}' });
        const j = await s.json();
        if (!s.ok || !j.url) return json({ error: 'sign', detail: j }, 500);
        one[k] = j.url;
      }
      out.push(one);
    }
    return json({ urls: out });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
