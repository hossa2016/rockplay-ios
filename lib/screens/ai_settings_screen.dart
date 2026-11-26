import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/ai_settings.dart';
import '../theme/app_theme.dart';
import '../widgets/section_header.dart';
import '../services/lastfm_service.dart';

/// Claves gratuitas de Groq y Gemini. Se guardan solo en este teléfono.
class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  final AiSettings _s = AiSettings.instance;
  final TextEditingController _groq = TextEditingController();
  final TextEditingController _gemini = TextEditingController();
  final TextEditingController _tavily = TextEditingController();
  final TextEditingController _setlist = TextEditingController();
  bool _hideSetlist = true;
  final TextEditingController _apify = TextEditingController();
  final TextEditingController _groqModel = TextEditingController();
  final TextEditingController _geminiModel = TextEditingController();
  bool _hideGroq = true;
  bool _hideGemini = true;
  bool _hideTavily = true;
  bool _hideApify = true;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _s.load();
    _groq.text = _s.groqKey;
    _gemini.text = _s.geminiKey;
    _tavily.text = _s.tavilyKey;
    _setlist.text = _s.setlistKey;
    _apify.text = _s.apifyKey;
    _groqModel.text = _s.groqModel;
    _geminiModel.text = _s.geminiModel;
    if (mounted) setState(() => _ready = true);
  }

  @override
  void dispose() {
    _groq.dispose();
    _gemini.dispose();
    _tavily.dispose();
    _setlist.dispose();
    _apify.dispose();
    _groqModel.dispose();
    _geminiModel.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    _s.groqKey = _groq.text;
    _s.geminiKey = _gemini.text;
    _s.tavilyKey = _tavily.text;
    _s.setlistKey = _setlist.text;
    _s.apifyKey = _apify.text;
    _s.groqModel = _groqModel.text;
    _s.geminiModel = _geminiModel.text;
    await _s.save();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Guardado en tu teléfono.')));
    Navigator.of(context).pop();
  }

  Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _paste(TextEditingController c) async {
    try {
      final d = await Clipboard.getData(Clipboard.kTextPlain);
      final t = (d?.text ?? '').trim();
      if (t.isEmpty) return;
      setState(() => c.text = t);
    } catch (_) {}
  }

  /// Tarjeta de una clave: estado, pasos, abrir página, pegar y campo.
  Widget _keyCard({
    required String name,
    required String subtitle,
    required String url,
    required String steps,
    required TextEditingController c,
    required bool hide,
    required VoidCallback toggle,
    required String hint,
  }) {
    final has = c.text.trim().isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: has
                      ? AppColors.amberTint
                      : AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(has ? 'Clave puesta' : 'Falta la clave',
                    style: TextStyle(
                        fontSize: AppType.caption,
                        fontWeight: FontWeight.w700,
                        color: has ? AppColors.amber : AppColors.textDim)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle,
              style: TextStyle(color: AppColors.textDim, fontSize: AppType.label)),
          const SizedBox(height: 12),
          Text(steps,
              style: const TextStyle(fontSize: AppType.label, height: 1.45)),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: OutlinedButton.icon(
              onPressed: () => _open(url),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Abrir la página'),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Pega aquí tu clave',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: AppType.label)),
          const SizedBox(height: 6),
          TextField(
            controller: c,
            obscureText: hide,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: hint,
              suffixIcon: IconButton(
                tooltip: hide ? 'Mostrar' : 'Ocultar',
                icon: Icon(hide
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                onPressed: toggle,
              ),
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: TextButton.icon(
              onPressed: () => _paste(c),
              icon: const Icon(Icons.content_paste_rounded, size: 18),
              label: const Text('Pegar clave'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _connectLastFm() async {
    final key = TextEditingController(), sec = TextEditingController(),
        user = TextEditingController(), pass = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Conectar Last.fm'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
                '1. En last.fm/api/account/create crea una «API account» (gratis).\n2. Copia la API key y el Shared secret.\n3. Escribe tu usuario y contraseña de Last.fm (la contraseña no se guarda).',
                style: TextStyle(color: AppColors.textDim, fontSize: AppType.label)),
            TextField(controller: key, decoration: const InputDecoration(labelText: 'API key')),
            TextField(controller: sec, decoration: const InputDecoration(labelText: 'Shared secret')),
            TextField(controller: user, decoration: const InputDecoration(labelText: 'Usuario')),
            TextField(
                controller: pass,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Contraseña')),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => launchUrl(Uri.parse('https://www.last.fm/api/account/create'),
                  mode: LaunchMode.externalApplication),
              child: const Text('Abrir la página')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Conectar')),
        ],
      ),
    );
    if (ok == true) {
      final err = await LastFmService.instance
          .connect(key.text, sec.text, user.text, pass.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(err == null ? 'Last.fm conectado.' : 'Last.fm: $err')));
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in [key, sec, user, pass]) {
        c.dispose();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: AppTitle('Claves del asistente')),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Text(
                  'El asistente usa primero Gemini y, si falla o se acaba el '
                  'límite gratis, usa Groq. Sin ninguna clave usa reglas simples. '
                  'Las claves se guardan solo en este teléfono.',
                  style: TextStyle(color: AppColors.textDim, height: 1.45),
                ),
                const SizedBox(height: 16),
                _keyCard(
                  name: 'Gemini (Google)',
                  subtitle: 'La principal. Gratis.',
                  url: 'https://aistudio.google.com/apikey',
                  steps:
                      '1. Toca «Abrir la página» e inicia sesión con Google.\n'
                      '2. Toca «Create API key» y copia la clave.\n'
                      '3. Vuelve aquí y toca «Pegar».',
                  c: _gemini,
                  hide: _hideGemini,
                  toggle: () => setState(() => _hideGemini = !_hideGemini),
                  hint: 'AIza…',
                ),
                _keyCard(
                  name: 'Groq',
                  subtitle: 'De respaldo. Gratis.',
                  url: 'https://console.groq.com/keys',
                  steps:
                      '1. Toca «Abrir la página» y crea tu cuenta.\n'
                      '2. Toca «Create API Key» y copia la clave.\n'
                      '3. Vuelve aquí y toca «Pegar».',
                  c: _groq,
                  hide: _hideGroq,
                  toggle: () => setState(() => _hideGroq = !_hideGroq),
                  hint: 'gsk_…',
                ),
                _keyCard(
                  name: 'Tavily (buscador web)',
                  subtitle: 'Para los conciertos. Gratis: 1.000 búsquedas al mes.',
                  url: 'https://app.tavily.com',
                  steps:
                      '1. Toca «Abrir la página» y crea tu cuenta (puedes usar Google).\n'
                      '2. En «API Keys» copia la clave que empieza por tvly-.\n'
                      '3. Vuelve aquí y toca «Pegar».',
                  c: _tavily,
                  hide: _hideTavily,
                  toggle: () => setState(() => _hideTavily = !_hideTavily),
                  hint: 'tvly-…',
                ),
                _keyCard(
                  name: 'setlist.fm (previa del concierto)',
                  subtitle: 'Opcional. Arma el setlist probable de tus bandas. Gratis para uso personal.',
                  url: 'https://www.setlist.fm/settings/api',
                  steps:
                      '1. Toca «Abrir la página» y crea tu cuenta gratis (Sign up).\n'
                      '2. En «API» toca «Apply for an API key»: en el uso escribe «Personal app, non-commercial».\n'
                      '3. Copia la clave que te dan, vuelve aquí y toca «Pegar».',
                  c: _setlist,
                  hide: _hideSetlist,
                  toggle: () => setState(() => _hideSetlist = !_hideSetlist),
                  hint: 'xxxxxxxx-xxxx-…',
                ),
                _keyCard(
                  name: 'Apify (Instagram de tus bares)',
                  subtitle: 'Opcional. Lee los flyers de tus bares. Gratis: 5 USD de crédito al mes.',
                  url: 'https://console.apify.com/settings/integrations',
                  steps:
                      '1. Toca «Abrir la página» y crea tu cuenta gratis (puedes usar Google).\n'
                      '2. En «API & Integrations» copia tu «Personal API token».\n'
                      '3. Vuelve aquí y toca «Pegar».\n'
                      '4. En Conciertos → Mis bares, escribe el @usuario de Instagram de cada bar.',
                  c: _apify,
                  hide: _hideApify,
                  toggle: () => setState(() => _hideApify = !_hideApify),
                  hint: 'apify_api_…',
                ),
                const SizedBox(height: 12),
                // Last.fm: registro opcional de lo que escuchas.
                ValueListenableBuilder<bool>(
                  valueListenable: LastFmService.instance.connected,
                  builder: (context, on, _) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.graphic_eq_rounded),
                      title: const Text('Last.fm (opcional)',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: ValueListenableBuilder<String>(
                        valueListenable: LastFmService.instance.lastError,
                        builder: (context, err, _) => Text(err.isNotEmpty
                            ? err
                            : on
                                ? 'Conectado como ${LastFmService.instance.user}. Registra lo que escuchas.'
                                : 'Registra lo que escuchas en tu perfil de Last.fm.'),
                      ),
                      trailing: TextButton(
                        onPressed: on
                            ? () => LastFmService.instance.disconnect()
                            : _connectLastFm,
                        child: Text(on ? 'Desconectar' : 'Conectar'),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Avanzado: modelos'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                        controller: _groqModel,
                        autocorrect: false,
                        decoration:
                            const InputDecoration(labelText: 'Modelo de Groq'),
                      ),
                    ),
                    TextField(
                      controller: _geminiModel,
                      autocorrect: false,
                      decoration:
                          const InputDecoration(labelText: 'Modelo de Gemini'),
                    ),
                    Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Si un modelo deja de existir, el asistente avisa '
                        '"modelo no encontrado". Cámbialo aquí por otro.',
                        style:
                            TextStyle(color: AppColors.textDim, fontSize: AppType.caption),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                FilledButton(onPressed: _save, child: const Text('Guardar')),
              ],
            ),
    );
  }
}
