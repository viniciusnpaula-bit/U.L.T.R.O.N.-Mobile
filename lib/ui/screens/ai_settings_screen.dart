import 'package:flutter/material.dart';
import '../../services/ai_provider_service.dart';

class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});
  @override State<AiSettingsScreen> createState()=>_AiSettingsScreenState();
}
class _AiSettingsScreenState extends State<AiSettingsScreen> {
  final store=AiProviderStore();
  final name=TextEditingController(text:'OpenAI-compatible');
  final url=TextEditingController(text:'https://api.openai.com/v1');
  final model=TextEditingController(text:'gpt-4o-mini');
  final key=TextEditingController();
  final prompt=TextEditingController(text:'Teste de conexão');
  List<AiProviderConfig> providers=[];
  bool busy=false, showKey=false;
  String status='Chaves ficam no armazenamento seguro do Android.';
  @override void initState(){super.initState();_load();}
  Future<void> _load() async {providers=await store.load();if(mounted)setState((){});}
  Future<void> _save() async {
    if(name.text.trim().isEmpty||url.text.trim().isEmpty||model.text.trim().isEmpty||key.text.trim().isEmpty){setState(()=>status='Preencha nome, URL, modelo e chave.');return;}
    final p=AiProviderConfig(id:DateTime.now().microsecondsSinceEpoch.toString(),name:name.text.trim(),baseUrl:url.text.trim(),model:model.text.trim(),apiKey:key.text.trim(),priority:providers.length);
    providers=[...providers,p];await store.save(providers);key.clear();setState(()=>status='Provedor salvo com segurança.'); 
  }
  Future<void> _test(AiProviderConfig p) async {setState(()=>busy=true);try{final answer=await AiFailover(store:store).test(p);status='Conexão OK: $answer';}catch(e){status='Falha: $e';}finally{if(mounted)setState(()=>busy=false);}}
  Future<void> _delete(AiProviderConfig p) async {providers.removeWhere((x)=>x.id==p.id);await store.save(providers);setState(()=>status='Provedor removido.');}
  Future<void> _toggle(AiProviderConfig p) async {providers=providers.map((x)=>x.id==p.id?AiProviderConfig(id:x.id,name:x.name,baseUrl:x.baseUrl,model:x.model,apiKey:x.apiKey,enabled:!x.enabled,priority:x.priority):x).toList();await store.save(providers);setState((){});}
  @override void dispose(){name.dispose();url.dispose();model.dispose();key.dispose();prompt.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>Scaffold(backgroundColor:const Color(0xFF0A0002),appBar:AppBar(title:const Text('Inteligência Artificial')),body:ListView(padding:const EdgeInsets.all(16),children:[
    const Text('Adicionar provedor compatível com API Chat Completions'),
    TextField(controller:name,decoration:const InputDecoration(labelText:'Nome do provedor')),
    TextField(controller:url,keyboardType:TextInputType.url,decoration:const InputDecoration(labelText:'URL base',hintText:'https://api.openai.com/v1')),
    TextField(controller:model,decoration:const InputDecoration(labelText:'Modelo')),
    TextField(controller:key,obscureText:!showKey,decoration:InputDecoration(labelText:'Chave API',suffixIcon:IconButton(icon:Icon(showKey?Icons.visibility_off:Icons.visibility),onPressed:()=>setState(()=>showKey=!showKey)))),
    SwitchListTile(value:showKey,onChanged:(v)=>setState(()=>showKey=v),title:const Text('Mostrar chave enquanto digito')),
    FilledButton(onPressed:_save,child:const Text('Salvar provedor')),
    const Divider(height:32),
    Text(status,style:const TextStyle(color:Color(0xFFFFA0A0))),
    const SizedBox(height:12),
    for(final p in providers) Card(child:ListTile(title:Text('${p.priority+1}. ${p.name}'),subtitle:Text('${p.model}\n${p.baseUrl}',maxLines:2,overflow:TextOverflow.ellipsis),leading:Switch(value:p.enabled,onChanged:(_)=>_toggle(p)),trailing:Wrap(spacing:0,children:[IconButton(onPressed:busy?null:()=>_test(p),icon:const Icon(Icons.wifi_tethering)),IconButton(onPressed:()=>_delete(p),icon:const Icon(Icons.delete_outline))]))),
    const SizedBox(height:8),const Text('Failover: provedores ativos são tentados em ordem de prioridade. Esta primeira versão usa endpoint compatível com OpenAI Chat Completions; Gemini nativo e Anthropic exigem adaptadores próprios.')
  ]));
}
