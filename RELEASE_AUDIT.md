# Auditoria de release candidate — 2026-07-19

## Veredito

**NOT READY**

A implementação local fecha as falhas de consistência, transporte, decode e
lifecycle encontradas na auditoria. O painel também foi aberto e conectado em
um Flutter DevTools real. A publicação, porém, continua bloqueada por um
resultado externo obrigatório: `all_observer` 1.5.6 hospedado não contém o
Observer Protocol v1. O runtime e o painel ainda precisam da branch Git
`protocol-v1`, portanto `flutter analyze` e `flutter pub publish --dry-run`
falham exatamente no gate que proíbe dependências Git.

Não é correto substituir essa dependência por `^1.5.6`: os símbolos do
protocolo não existem nessa versão e o projeto deixa de compilar. É necessário
publicar primeiro uma versão numerada de `all_observer` com o protocolo v1.

## Baseline

Baseline limpo: commit `76c81d3264fb342e32d5eaff07f03bc59b94dad0`.

- Flutter 3.44.6, Dart 3.12.2 e DevTools 2.57.0.
- Raiz: `pub get` passou, 43 testes passaram e `flutter analyze` encontrou
  somente a dependência Git publicável.
- Painel: `pub get`, 24 testes e `flutter analyze` passaram.
- Web release build, `build_and_copy` e `devtools_extensions validate`
  passaram.
- Publish dry-run gerou um arquivo de 15 MB, contendo o painel compilado, mas
  falhou pela dependência Git e pela recomendação de usar a versão hospedada.
- O comando de build inicialmente solicitado com `--dest=../devtools/build`
  cria `build/build`; o destino correto confirmado contra a CLI instalada é
  `--dest=../devtools`.

## Hipóteses reproduzidas e correções

| Falha / hipótese | Reprodução antes da correção | Correção e cobertura |
| --- | --- | --- |
| Snapshot e polling pertencem a sessões diferentes | Poll retornando outra sessão depois do snapshot era aceito | A tentativa inteira é descartada e refeita; snapshot, backlog e live pendente precisam ter a mesma sessão |
| Poll vazio esconde uma sequência não representada | `events: []` com `lastSequenceNumber` além do snapshot permitia uma janela silenciosa | O tail do poll participa da reconciliação e força retry quando há sequência não representada |
| Resync só reagia a gap explícito | Evento semanticamente impossível marcava `needsResync`, mas não buscava snapshot | Toda inconsistência semântica dispara o mesmo resync single-flight |
| Falha assíncrona do snapshot de resync escapava | Exceção ficava não tratada e o controller permanecia conectado | Erro é capturado, sanitizado, muda o estado para erro e uma tentativa posterior pode recuperar |
| Callback atrasado após dispose | Batch já enfileirado podia tocar estado descartado | Callbacks e conclusão tardia de `streamListen` verificam dispose; inscrição tardia é cancelada |
| Adapter mudava de isolate no meio do handshake | Chamadas liam o isolate selecionado dinamicamente e eventos VM-wide não eram filtrados | Cada conexão captura serviço+isolate imutáveis; chamadas e stream ficam vinculados e eventos de outros isolates são ignorados |
| Troca de target não recriava a conexão | O app mantinha adapter/controller antigos em reconnect, isolate switch e hot restart | Listeners de conexão e isolate recriam e descartam o par inteiro, sem permitir resposta antiga |
| Erros de transporte/decode expunham payload | Mensagens podiam interpolar mapas e valores recebidos | Diagnósticos mostram apenas categoria/campo/tipo; payload bruto e valores potencialmente sensíveis não são ecoados |
| Envelope aceitou ranges impossíveis | Sequência zero e tail ausente/inválido passavam em alguns casos | `EventBatchModel` valida range completo, inclusive batches vazios |
| Descarte explícito era silencioso | `clearPending` e dispose removiam eventos sem contador | `transportClearedEventCount` é contabilizado e exposto por `getStatus` |
| Limite podia divergir do payload real | Casos Unicode e envelope completo não estavam cobertos explicitamente | Limite usa UTF-8 do JSON completo; testes cobrem ASCII, acentos, emoji, labels longos, stack trace, limite exato e ±1 byte |

Os testes novos foram escritos para falhar antes das correções correspondentes.
Fakes de contrato foram ajustados para não produzirem ranges impossíveis que o
registrar real nunca retornaria.

## Evidência automatizada final

- Raiz: **44 testes passaram**.
- Painel: **33 testes passaram**.
- `flutter analyze` do painel: **sem issues**.
- `flutter analyze` da raiz: **1 warning**, somente a dependência Git proibida.
- `flutter build web --release`: passou; apenas mensagens informativas de
  tree-shaking/Wasm.
- `devtools_extensions build_and_copy --source=. --dest=../devtools`: passou.
- `devtools_extensions validate --package=../..`: **Extension validation
  successful**.
- Publish dry-run: arquivo compactado de **15 MB**, com licença, changelog,
  exemplo e um único `extension/devtools/build`; falhou com a dependência Git,
  a recomendação de fonte hospedada e, nesta árvore de trabalho, o aviso
  transitório de arquivos modificados.

## Evidência em DevTools real

Ambiente: Chrome 150, app Flutter Web debug iniciado por `flutter run`, Flutter
DevTools 2.57.0 conectado ao VM Service do app.

- O diálogo **DevTools Extensions** descobriu `package:all_observer` e mostrou
  a extensão como habilitada.
- O tab `all_observer` carregou o build empacotado em um iframe servido pelo
  host real do DevTools.
- O Overview negociou protocolo 1 e exibiu `Streaming connected`, 15 nós
  ativos, 5 arestas e 3 scopes, sem necessidade de resync.
- Após reload completo do app, o DevTools mostrou o main isolate pausado e o
  painel exibiu erro sanitizado. Depois de `Resume` + `Retry`, o painel
  conectou em uma **nova session id**, voltou a `Streaming connected` e
  reaplicou o snapshot; o binding antigo não foi reutilizado.
- Ao encerrar o processo Flutter, o host removeu o iframe e passou para
  `Disconnected` / `No client connection`, sem manter o painel aparentando uma
  conexão viva.
- O adapter foi conferido diretamente contra as APIs instaladas de
  `devtools_extensions` 0.5.1, `devtools_app_shared` 0.5.1 e `vm_service`
  15.2.0. A seleção é um `ValueListenable<IsolateRef?>`, os eventos de extensão
  carregam `isolate`, e RPC 103 é o caso de stream já inscrito.

Essa evidência comprova descoberta, enablement, iframe real, handshake,
snapshot, streaming e recuperação após troca de sessão. Ela não é apresentada
como prova de todos os cenários manuais listados abaixo.

## Antes / depois

| Área | Antes | Depois |
| --- | --- | --- |
| Janela de conexão | Snapshot/backlog podiam ser aceitos entre sessões ou com tail oculto | Snapshot, poll e live são reconciliados por sessão, range e sequência com retry limitado |
| Resync | Falha assíncrona escapava; inconsistência semântica não iniciava resync | Single-flight, erro tratado, retry recuperável e gatilho por qualquer `needsResync` |
| Isolate/lifecycle | Binding lido dinamicamente; subscription tardia | Binding imutável, filtro por isolate, controller recriado e late callbacks ignorados |
| Decode | Alguns erros ecoavam o mapa recebido | Erros estritos e sanitizados, com estado visível |
| Perdas no transporte | Drop oversized visível, clear/dispose silenciosos | Drops e clears têm contadores separados no status |
| Payload | Cobertura parcial | UTF-8 do envelope completo e fronteiras exatas cobertas |
| Testes | 43 raiz + 24 painel | 44 raiz + 33 painel |
| DevTools real | Não exercitado | Extensão descoberta, aberta, conectada e recuperada em nova sessão |

## Riscos residuais e checklist de release

- [x] Snapshot + backlog + live stream sem janela, com batcher/registrar/client reais.
- [x] Resync single-flight, bounded retry e proteção contra geração obsoleta.
- [x] Contrato vazio/não vazio/evicted de `getEvents`.
- [x] Limite real de payload UTF-8 e perdas de transporte visíveis.
- [x] Registro duplicado esperado separado de falha inesperada.
- [x] Decode estrito, sanitizado e com falha visível.
- [x] Adapter compilado e APIs instaladas verificadas diretamente.
- [x] Build release copiado, painel não vazio/atualizado e validate aprovado.
- [x] Smoke test real de descoberta, enablement, conexão e recuperação de sessão.
- [x] Encerramento do app refletido como desconectado pelo host real.
- [x] CI separado para runtime, painel, contratos, payload, build/validate e publish.
- [ ] Publicar Observer Protocol v1 em uma versão hospedada de `all_observer`.
- [ ] Trocar as duas dependências Git pela constraint dessa versão.
- [ ] Reexecutar analyze e publish dry-run em commit limpo e obter zero warnings.
- [ ] Exercitar manualmente troca entre dois isolates reais.
- [ ] Exercitar hot reload e hot restart pelos comandos do Flutter, além do reload
  completo já validado.
- [ ] Exercitar reconexão de um novo processo, versão incompatível em host real,
  carga sustentada, disposes, warnings e values/redaction no painel real.

Como os critérios de aprovação exigem publish dry-run aprovado, ausência de
dependência Git e toda a matriz manual, o único veredito tecnicamente honesto é
**NOT READY**.
