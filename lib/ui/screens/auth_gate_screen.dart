import 'package:flutter/material.dart';
import '../../services/ultron_auth_service.dart';
import 'core_screen.dart';

class AuthGateScreen extends StatefulWidget {
  const AuthGateScreen({super.key});
  @override
  State<AuthGateScreen> createState() => _AuthGateScreenState();
}

class _AuthGateScreenState extends State<AuthGateScreen> with WidgetsBindingObserver {
  final _auth = UltronAuthService();
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  bool _setup = false, _busy = true, _showPin = false, _biometric = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    final hasPin = await _auth.hasPin();
    final biometric = await _auth.canUseBiometrics();
    if (!mounted) return;
    setState(() { _setup = !hasPin; _biometric = biometric; _busy = false; });
    if (hasPin && biometric) _unlockBiometric();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_setup && !_busy) {
      setState(() { _busy = true; _error = null; });
      _initialize();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pin.dispose(); _confirm.dispose(); super.dispose();
  }

  Future<void> _submitPin() async {
    final pin = _pin.text;
    setState(() { _error = null; _busy = true; });
    if (_setup) {
      if (pin != _confirm.text) {
        setState(() { _busy = false; _error = 'Os PINs não coincidem.'; }); return;
      }
      try { await _auth.setPin(pin); } catch (e) {
        setState(() { _busy = false; _error = e.toString().replaceFirst('ArgumentError: ', ''); }); return;
      }
    } else if (!await _auth.verifyPin(pin)) {
      setState(() { _busy = false; _error = 'PIN incorreto.'; _pin.clear(); }); return;
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const CoreScreen()));
  }

  Future<void> _unlockBiometric() async {
    setState(() { _busy = true; _error = null; });
    final ok = await _auth.authenticateBiometric();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const CoreScreen()));
    } else {
      setState(() { _busy = false; _error = 'Biometria não reconhecida. Use seu PIN.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFE50914);
    return Scaffold(
      backgroundColor: const Color(0xFF080003),
      body: SafeArea(child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(26),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Column(
          mainAxisSize: MainAxisSize.min, children: [
            Container(width: 112,height: 112,decoration: BoxDecoration(shape: BoxShape.circle,border: Border.all(color: red.withOpacity(.55)),boxShadow:[BoxShadow(color:red.withOpacity(.15),blurRadius:32)]),
              child: const Icon(Icons.shield_moon_outlined,color:red,size:54)),
            const SizedBox(height: 28),
            const Text('U.L.T.R.O.N.',style: TextStyle(color:red,fontSize:24,fontWeight:FontWeight.w900,letterSpacing:4)),
            const SizedBox(height: 8),
            Text(_setup ? 'CONFIGURAÇÃO DE SEGURANÇA' : 'ACESSO PROTEGIDO',style: const TextStyle(color:Colors.white54,fontSize:10,letterSpacing:2)),
            const SizedBox(height: 30),
            if (_busy) const CircularProgressIndicator(color:red)
            else ...[
              Text(_setup ? 'Crie um PIN de 4 a 8 dígitos para proteger o núcleo.' : 'Autentique-se para continuar.',textAlign:TextAlign.center,style:const TextStyle(color:Colors.white70)),
              const SizedBox(height: 22),
              TextField(controller:_pin,keyboardType:TextInputType.number,obscureText:!_showPin, maxLength:8,
                decoration:InputDecoration(labelText:_setup?'Criar PIN':'PIN de acesso',counterText:'',suffixIcon:IconButton(icon:Icon(_showPin?Icons.visibility_off:Icons.visibility),onPressed:()=>setState(()=>_showPin=!_showPin))),
              ),
              if (_setup) ...[
                const SizedBox(height:12),
                TextField(controller:_confirm,keyboardType:TextInputType.number,password:!_showPin,maxLength:8,
                  decoration:const InputDecoration(labelText:'Confirmar PIN',counterText:'')),
              ],
              if (_error != null) Padding(padding:const EdgeInsets.only(top:14),child:Text(_error!,style:const TextStyle(color:Colors.redAccent),textAlign:TextAlign.center)),
              const SizedBox(height:22),
              SizedBox(width:double.infinity,child:FilledButton(onPressed:_submitPin,style:FilledButton.styleFrom(backgroundColor:const Color(0xFFFFB4AB),foregroundColor:const Color(0xFF390008),padding:const EdgeInsets.symmetric(vertical:16)),child:Text(_setup?'SALVAR PIN':'ENTRAR COM PIN'))),
              if (!_setup && _biometric) ...[
                const SizedBox(height:12),
                SizedBox(width:double.infinity,child:OutlinedButton.icon(onPressed:_unlockBiometric,icon:const Icon(Icons.face),label:const Text('AUTENTICAR COM BIOMETRIA'))),
              ],
            ],
            const SizedBox(height:24),
            const Text('A biometria é verificada pelo Android. O U.L.T.R.O.N. não armazena imagens faciais.',textAlign:TextAlign.center,style:TextStyle(color:Colors.white30,fontSize:10)),
          ],
        ))),
      )),
    );
  }
}
