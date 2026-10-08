// Assistant de rédaction des devis (Supabase Edge Function).
// La clé de l'IA reste ici, en secret côté serveur : la page n'y a jamais accès.
//
// Deux actions :
// - « devis » : propose les lignes d'un devis à partir de la description du chantier,
//   en reprenant les libellés de la bibliothèque de l'utilisateur. Les prix ne sont pas
//   envoyés à l'IA : la page les remet elle-même sur les lignes reconnues ;
// - « reformuler » : réécrit les descriptions des lignes de façon professionnelle.
//
// Secrets à définir dans Supabase (Edge Functions > Secrets), selon l'IA choisie :
// - MISTRAL_API_KEY : clé de l'API Mistral (console.mistral.ai, offre gratuite « Experiment ») ;
//   MISTRAL_MODEL (facultatif) : modèle, mistral-small-latest par défaut ;
// - ou ANTHROPIC_API_KEY : clé de l'API Claude (console.anthropic.com, payante) ;
//   ANTHROPIC_MODEL (facultatif) : modèle, Claude Haiku par défaut.
// Si les deux clés sont présentes, Mistral est utilisée.
// La page masque les données personnelles (client, adresses, emails, téléphones) avant l'envoi.
// Chaque compte est limité à un nombre de demandes par jour (fonction ia_consommer de schema.sql).

import { createClient } from 'npm:@supabase/supabase-js@2';

const MISTRAL_KEY = Deno.env.get('MISTRAL_API_KEY') || '';
const ANTHROPIC_KEY = Deno.env.get('ANTHROPIC_API_KEY') || '';
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const reply = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });

const text = (v: unknown, max: number) => (typeof v === 'string' ? v : '').trim().slice(0, max);
const num = (v: unknown) => (typeof v === 'number' && isFinite(v) ? v : Number(v) || 0);

type Ligne = { d: string; q: number; u: string; bibliotheque: boolean };

const TOOL_DEVIS = {
  name: 'remplir_devis',
  description: 'Lignes proposées pour le devis.',
  input_schema: {
    type: 'object',
    properties: {
      lignes: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            d: { type: 'string', description: 'Description de la prestation' },
            q: { type: 'number', description: 'Quantité' },
            u: { type: 'string', description: 'Unité : u, m², ml, m³, h, jour, forfait, kg, lot, ens. ou autre' },
            bibliotheque: { type: 'boolean', description: 'true si la ligne reprend une prestation de la bibliothèque' },
          },
          required: ['d', 'q', 'u', 'bibliotheque'],
        },
      },
      remarques: { type: 'string', description: 'Calculs de quantités, hypothèses et points à vérifier, en quelques phrases' },
    },
    required: ['lignes', 'remarques'],
  },
};

const TOOL_REFORMULER = {
  name: 'reformuler',
  description: 'Descriptions reformulées, dans le même ordre.',
  input_schema: {
    type: 'object',
    properties: {
      lignes: {
        type: 'array',
        items: {
          type: 'object',
          properties: { i: { type: 'integer' }, d: { type: 'string' } },
          required: ['i', 'd'],
        },
      },
    },
    required: ['lignes'],
  },
};

const SYSTEM_DEVIS = `Tu aides un artisan du bâtiment à rédiger un devis en français.
À partir de la description du chantier, propose les lignes de prestations et de fournitures.
Règles :
- Utilise en priorité les prestations de la bibliothèque fournie : recopie exactement le libellé et l'unité (bibliotheque = true).
- Pour une prestation absente de la bibliothèque, rédige une description professionnelle (bibliotheque = false). Ne donne aucun prix : l'artisan les fixe.
- Les informations personnelles ont été remplacées par des repères entre crochets ([CLIENT], [ADRESSE]…) : recopie-les tels quels si besoin, sans les modifier.
- Calcule les quantités à partir des dimensions données (ex. murs d'une pièce = périmètre × hauteur ; plafond = surface au sol). Arrondis à 2 décimales.
- Si une quantité ne peut pas être déduite, mets 1 avec l'unité la plus logique et signale-le dans les remarques.
- Respecte l'ordre logique du chantier (protection, dépose, préparation, travaux, finitions, nettoyage).
- Ne propose que des travaux demandés ou indispensables à ceux-ci ; n'ajoute pas d'options.
- Dans les remarques, explique brièvement les calculs et ce que l'artisan doit vérifier.`;

const SYSTEM_REFORMULER = `Tu aides un artisan du bâtiment à rédiger un devis en français.
Reformule chaque description de prestation pour qu'elle soit claire, précise et professionnelle :
orthographe corrigée, vocabulaire du métier, détail des travaux réellement mentionnés.
N'ajoute aucun travail qui n'est pas dans la description d'origine, ne mentionne ni quantité ni prix.
Les repères entre crochets ([CLIENT], [ADRESSE]…) remplacent des informations personnelles : recopie-les tels quels.
Reste concis : une phrase, 200 caractères au plus. Garde le même numéro i pour chaque ligne.`;

type Tool = typeof TOOL_DEVIS | typeof TOOL_REFORMULER;

// Demande à l'IA de répondre en remplissant l'outil (réponse structurée en JSON)
async function askMistral(system: string, tool: Tool, content: string) {
  const res = await fetch('https://api.mistral.ai/v1/chat/completions', {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + MISTRAL_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: Deno.env.get('MISTRAL_MODEL') || 'mistral-small-latest',
      max_tokens: 4000,
      temperature: 0.2,
      messages: [{ role: 'system', content: system }, { role: 'user', content }],
      tools: [{ type: 'function', function: { name: tool.name, description: tool.description, parameters: tool.input_schema } }],
      tool_choice: 'any',
    }),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error('IA ' + res.status + ' : ' + (data?.message || data?.error?.message || data?.detail || 'erreur inconnue'));
  const args = data.choices?.[0]?.message?.tool_calls?.[0]?.function?.arguments;
  if (!args) throw new Error('Réponse de l\'IA inattendue');
  return typeof args === 'string' ? JSON.parse(args) : args;
}

async function askClaude(system: string, tool: Tool, content: string) {
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'x-api-key': ANTHROPIC_KEY,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      model: Deno.env.get('ANTHROPIC_MODEL') || 'claude-haiku-5-5',
      max_tokens: 4000,
      system,
      tools: [tool],
      tool_choice: { type: 'tool', name: tool.name },
      messages: [{ role: 'user', content }],
    }),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error('IA ' + res.status + ' : ' + (data?.error?.message || 'erreur inconnue'));
  const out = (data.content || []).find((c: { type: string }) => c.type === 'tool_use');
  if (!out) throw new Error('Réponse de l\'IA inattendue');
  return out.input;
}

const askAI = (system: string, tool: Tool, content: string) =>
  MISTRAL_KEY ? askMistral(system, tool, content) : askClaude(system, tool, content);

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return reply(405, { error: 'Méthode non autorisée' });
  if (!MISTRAL_KEY && !ANTHROPIC_KEY) return reply(500, { error: 'Clé de l\'IA absente : ajoutez MISTRAL_API_KEY dans les secrets des Edge Functions' });

  // Utilisateur connecté obligatoire : le jeton de la page est vérifié auprès de Supabase
  const auth = req.headers.get('Authorization') || '';
  const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY') || req.headers.get('apikey') || '', {
    global: { headers: { Authorization: auth } },
  });
  const { data: { user } } = await sb.auth.getUser(auth.replace(/^Bearer\s+/i, ''));
  if (!user) return reply(401, { error: 'Connexion requise' });

  const body = await req.json().catch(() => ({}));
  const action = body.action;
  if (action !== 'devis' && action !== 'reformuler') return reply(400, { error: 'Action inconnue' });

  // Demande vérifiée avant de compter une utilisation
  const description = text(body.texte, 4000);
  const biblio = (Array.isArray(body.bibliotheque) ? body.bibliotheque : []).slice(0, 400)
    .map((i: Record<string, unknown>) => ({ metier: text(i.metier, 60), d: text(i.d, 300), u: text(i.u, 12) }))
    .filter((i: { d: string }) => i.d);
  const aReformuler = (Array.isArray(body.lignes) ? body.lignes : []).slice(0, 100)
    .map((d: unknown, i: number) => ({ i, d: text(d, 500) }));
  if (action === 'devis' && !description) return reply(400, { error: 'Description du chantier vide' });
  if (action === 'reformuler' && !aReformuler.some((l: { d: string }) => l.d)) return reply(400, { error: 'Aucune description à reformuler' });

  // Quota quotidien par compte
  const { data: allowed, error: quotaError } = await sb.rpc('ia_consommer');
  if (quotaError) return reply(500, { error: 'Quota : ' + quotaError.message, code: quotaError.code });
  if (!allowed) return reply(429, { error: 'Limite quotidienne de l\'assistant atteinte. Réessayez demain.' });

  try {
    if (action === 'devis') {
      const out = await askAI(SYSTEM_DEVIS, TOOL_DEVIS,
        'Bibliothèque de prestations :\n' + JSON.stringify(biblio) +
        '\n\nDescription du chantier :\n' + description);
      const lignes: Ligne[] = (Array.isArray(out.lignes) ? out.lignes : []).slice(0, 60).map((l: Record<string, unknown>) => ({
        d: text(l.d, 300),
        q: Math.min(Math.max(Math.round(num(l.q) * 100) / 100, 0), 1e6) || 1,
        u: text(l.u, 12),
        bibliotheque: l.bibliotheque === true,
      })).filter((l: Ligne) => l.d);
      return reply(200, { lignes, remarques: text(out.remarques, 2000) });
    }

    const out = await askAI(SYSTEM_REFORMULER, TOOL_REFORMULER, JSON.stringify(aReformuler.filter((l: { d: string }) => l.d)));
    const result: string[] = aReformuler.map((l: { d: string }) => l.d);
    for (const l of Array.isArray(out.lignes) ? out.lignes : []) {
      const i = Number(l.i), d = text(l.d, 300);
      if (Number.isInteger(i) && i >= 0 && i < result.length && result[i] && d) result[i] = d;
    }
    return reply(200, { lignes: result });
  } catch (e) {
    console.error(e);
    return reply(502, { error: e instanceof Error ? e.message : String(e) });
  }
});
