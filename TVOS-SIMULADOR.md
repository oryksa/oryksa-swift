# OryksaTV no simulador da Apple TV (passos para o Mac)

Escrito a 27/11/2026 num PC com Windows, sem Xcode e sem Swift. **Nada disto foi compilado nem corrido ainda.** A prova é de quem corre estes passos no Mac. No fim (secção 6) está o que fica provado e o que NÃO fica.

Regras de sempre:
- O token de teste nunca vai para o repositório nem para a linha de comandos. Usa-se um ficheiro fora do repositório e passa-se só o caminho.
- Nunca mostrar nenhum carácter do token. Para confirmar o ficheiro, ver só o tamanho (`wc -c`).
- Os testes normais nunca chamam o servidor real. O teste ao vivo só corre com `ORYKSA_LIVE=1` e gasta interações da conta de TESTE.

## 0. O que é preciso

- Um Mac com Xcode 15 ou mais recente e o simulador do tvOS instalado (Xcode > Settings > Components > tvOS).
- Para a app de demonstração: o XcodeGen, o mesmo que o `Example/` e o CI já usam (`brew install xcodegen`). Sem XcodeGen, ver a secção 3.5.
- Os comandos correm na raiz deste repositório (a pasta do `Package.swift`).
- Uma pasta para as provas, FORA do repositório:

```sh
export PROVAS=~/oryksa-tv-provas/$(date +%Y%m%d-%H%M)
mkdir -p "$PROVAS"
```

## 1. Escolher e arrancar o simulador

```sh
xcrun simctl list devices available | grep -A20 -- "-- tvOS"
export TV_UDID=$(xcrun simctl list devices available -j | python3 -c "import json,sys;d=json.load(sys.stdin)['devices'];print(next(x['udid'] for k,v in d.items() if 'tvOS' in k for x in v if x['name'].startswith('Apple TV')))")
echo "$TV_UDID"
xcrun simctl boot "$TV_UDID"; xcrun simctl bootstatus "$TV_UDID" -b
open -a Simulator
```

Se houver vários runtimes do tvOS, corre também no mais antigo que existir (o mínimo do pacote é o tvOS 15) e diz qual foi.

## 2. Testes unitários (HTTP simulado, sem servidor real)

### 2.1 No macOS (rápido, o mesmo que o CI)

```sh
swift test 2>&1 | tee "$PROVAS/unit-macos.log"
```

### 2.2 No simulador do tvOS

```sh
xcodebuild test -scheme Oryksa-Package -destination "id=$TV_UDID" \
  -resultBundlePath "$PROVAS/unit-tvos.xcresult" CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$PROVAS/unit-tvos.log"
```

- `Oryksa-Package` é o esquema que o Xcode cria para o pacote, com todos os alvos e os dois alvos de testes (`OryksaTests` e `OryksaTVTests`). Se tiver outro nome: `xcodebuild -list`.
- Em vez do UDID também serve `-destination 'platform=tvOS Simulator,name=Apple TV'`.
- Só os testes de TV: acrescentar `-only-testing:OryksaTVTests`.
- Esperado: `** TEST SUCCEEDED **`, com o `TVLiveTests` como *skipped*.
- Confirmar também que o iOS e o tvOS compilam:

```sh
xcodebuild -scheme Oryksa -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
xcodebuild -scheme Oryksa -destination 'generic/platform=tvOS' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
xcodebuild -scheme OryksaTV -destination 'generic/platform=tvOS' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

O que estes testes cobrem (o contrato de cobrança é o mais importante):
- cada fala pede `POST /v1/client/tts`, também a repetida (com `cached: true` e o `voice_rev`) e a só com legendas (`voice: false`);
- a fala só aparece e só toca com `X-ORYKSA-Interactions-Spent` >= 1; sem o cabeçalho, ou com 0, o `onError` recebe `not_counted`;
- 402 `interactions_exhausted`: nada aparece e os pedaços seguintes não são pedidos;
- erro de rede: nada aparece;
- textos maiores do que o limite vão em pedaços;
- a configuração (`GET /v1/client/agent?locale=`, bloco `tv`), o emparelhamento (`POST`, eventos por long-poll, `DELETE`), a sessão pública com `platform` e `app_id`, e o `platform` em todos os pedidos.

### 2.3 Teste ao vivo (opcional, GASTA interações da conta de TESTE)

Diz 3 falas no servidor real: uma nova, a mesma outra vez e uma só com legendas. Cada uma é cobrada pela tabela de custos de interação da ORYKSA.

Guardar o token público do chat da conta de TESTE num ficheiro (o `read -s` não mostra o que se escreve e nada fica no histórico):

```sh
mkdir -p ~/.oryksa && chmod 700 ~/.oryksa
read -rs -p "Token público do chat (conta de TESTE): " T; echo; printf '%s' "$T" > ~/.oryksa/tv-test-token; unset T
chmod 600 ~/.oryksa/tv-test-token
wc -c < ~/.oryksa/tv-test-token   # só o tamanho
```

No macOS:

```sh
ORYKSA_LIVE=1 ORYKSA_TV_TOKEN_FILE="$HOME/.oryksa/tv-test-token" ORYKSA_PROOF_OUT="$PROVAS/live-macos.txt" \
  swift test --filter TVLiveTests 2>&1 | tee "$PROVAS/live-macos.log"
```

No simulador do tvOS (o `xcodebuild` passa ao teste as variáveis com o prefixo `TEST_RUNNER_`, já sem o prefixo):

```sh
TEST_RUNNER_ORYKSA_LIVE=1 TEST_RUNNER_ORYKSA_TV_TOKEN_FILE="$HOME/.oryksa/tv-test-token" \
TEST_RUNNER_ORYKSA_PROOF_OUT="$PROVAS/live-tvos.txt" \
xcodebuild test -scheme Oryksa-Package -destination "id=$TV_UDID" -only-testing:OryksaTVTests/TVLiveTests \
  -resultBundlePath "$PROVAS/live-tvos.xcresult" CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$PROVAS/live-tvos.log"
```

Esperado no `live-*.txt` (só estados, cabeçalhos e tamanhos, nunca o token):
1. a fala nova: `status=200`, `spent` >= 1, `cached_rev=-`;
2. a mesma fala: `status=204`, `voice_status=cached`, `spent` >= 1, enviada com `cached_rev`, e a voz guardada toca (`player.loaded` com o mesmo ficheiro duas vezes);
3. só legendas: `status=204`, `voice_status=captions`, `spent` >= 1, e a legenda aparece (`shown`).

O resumo também fica como anexo `tv-live-proof.txt` no `.xcresult`.

A confirmar no Mac: o simulador corre no disco do Mac, por isso o teste deve conseguir ler o ficheiro do token e escrever o `ORYKSA_PROOF_OUT`. Se não conseguir, usar `TEST_RUNNER_ORYKSA_TV_TOKEN="$(cat ~/.oryksa/tv-test-token)"` (a linha mostra o `cat`, não o token) e não partilhar esse `.xcresult` sem verificar (secção 5).

## 3. A app de demonstração (ExampleTV)

Os botões: "Ouvir a apresentadora", "Abrir o assistente", "Falar pelo celular/telemóvel", "Mudar o idioma" e "Só legendas". Sem token corre SIMULADA (banda laranja): não prova nada do servidor.

### 3.1 Gerar o projeto e compilar

```sh
cd ExampleTV
xcodegen
xcodebuild build -project OryksaTVDemo.xcodeproj -scheme OryksaTVDemo -destination "id=$TV_UDID" \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$PROVAS/demo-build.log"
xcrun simctl install "$TV_UDID" build/Build/Products/Debug-appletvsimulator/OryksaTVDemo.app
```

O `.xcodeproj` gerado e a pasta `build/` estão no `.gitignore`.

### 3.2 Correr simulada

```sh
xcrun simctl launch --console-pty "$TV_UDID" com.oryksa.tvdemo -lang pt-BR
```

O comando no simulador: setas do teclado, Enter = OK, Esc = Voltar; ou a janela do comando (menu do Simulador, I/O ou Hardware > Show Apple TV Remote, conforme a versão).

### 3.3 Correr com o servidor real (conta de TESTE)

O `simctl launch` passa à app as variáveis com o prefixo `SIMCTL_CHILD_`, já sem o prefixo. Só vai o caminho do ficheiro:

```sh
SIMCTL_CHILD_ORYKSA_CHAT_TOKEN_FILE="$HOME/.oryksa/tv-test-token" \
  xcrun simctl launch --console-pty --terminate-running-process "$TV_UDID" com.oryksa.tvdemo -lang pt-BR \
  2>&1 | tee "$PROVAS/demo-real-console.log"
```

Sem banda laranja = modo real. No Xcode, em vez disto: Product > Scheme > Edit Scheme > Run > Arguments > Environment Variables, `ORYKSA_CHAT_TOKEN_FILE` = o caminho do ficheiro (não marcar o esquema como *Shared*).

### 3.4 Argumentos da app

- `-lang <locale>`: a primeira língua (`pt-BR`, `pt-PT`, `es-MX`, `es-ES`, `fr-FR`, `de-DE`, `en-US`, `en-GB`).
- `-oryksaProof YES`: mostra no ecrã, a amarelo, a última resposta do tts (para o teste de interface e para os vídeos de prova).
- `-oryksaFreshCache YES`: começa sem falas guardadas (uma pasta nova; nada é apagado).

### 3.5 Sem XcodeGen

1. Xcode > File > New > Project > tvOS > App (SwiftUI). Nome `OryksaTVDemo`, bundle id `com.oryksa.tvdemo`, guardado fora do repositório.
2. Apagar o `ContentView.swift` e o ficheiro `...App.swift` gerados e arrastar `ExampleTV/Sources/*.swift`.
3. File > Add Package Dependencies > Add Local... > a raiz deste repositório > produto `OryksaTV`.
4. Para o teste de interface: File > New > Target > tvOS > UI Testing Bundle, e arrastar `ExampleTV/UITests/DemoUITests.swift`.
5. Nos passos seguintes usar esse projeto em vez de `OryksaTVDemo.xcodeproj`.

## 4. Teste de interface (XCUITest, só com o comando)

O teste `testPresenterNewLineSameLineCachedAndSubtitlesOnlyWithTheRemote`:
1. abre a app (com `-oryksaProof YES -oryksaFreshCache YES -lang en-US`) e confirma que o primeiro botão tem o foco;
2. OK em "Hear the host": espera o `tts#1` (fala nova, `cached_rev=-`, com `interactions_spent`) e a legenda; captura;
3. OK outra vez: espera o `tts#2` com `cached_rev` e `voice_status=cached`; captura;
4. setas até "Subtitles only" e OK: espera o `tts#3` com `voice=false` e `voice_status=captions`; captura.

O teste `testOkAndBackStopHerAndTheKeyIsNotPassedOn` (só simulado, para não gastar interações): o OK e o Voltar calam a apresentadora; o OK que a calou não carrega outra vez no botão (o contador continua no mesmo `tts#`); o Voltar não sai da app.

Para gravar vídeo da prova, noutro terminal, antes de começar (Ctrl+C no fim):

```sh
xcrun simctl io "$TV_UDID" recordVideo --codec h264 "$PROVAS/ui.mp4"
```

Simulado:

```sh
cd ExampleTV
TEST_RUNNER_ORYKSA_PROOF_DIR="$PROVAS/ui-simulado" \
xcodebuild test -project OryksaTVDemo.xcodeproj -scheme OryksaTVDemo -destination "id=$TV_UDID" \
  -resultBundlePath "$PROVAS/ui-simulado.xcresult" CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$PROVAS/ui-simulado.log"
```

Real (conta de TESTE, gasta 3 falas):

```sh
cd ExampleTV
TEST_RUNNER_ORYKSA_CHAT_TOKEN_FILE="$HOME/.oryksa/tv-test-token" TEST_RUNNER_ORYKSA_PROOF_DIR="$PROVAS/ui-real" \
xcodebuild test -project OryksaTVDemo.xcodeproj -scheme OryksaTVDemo -destination "id=$TV_UDID" \
  -only-testing:OryksaTVDemoUITests/DemoUITests/testPresenterNewLineSameLineCachedAndSubtitlesOnlyWithTheRemote \
  -resultBundlePath "$PROVAS/ui-real.xcresult" CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$PROVAS/ui-real.log"
```

Uma captura à mão, a qualquer momento: `xcrun simctl io "$TV_UDID" screenshot "$PROVAS/ecra.png"`.

À mão (o teste de interface não cobre): abrir o assistente, andar pelas perguntas com as setas, escrever com o teclado do sistema (só o botão Enviar envia), o Voltar fecha o painel; o cartão do telemóvel mostra o QR do servidor (real) ou o código (simulado); "Mudar o idioma" muda o ecrã, os textos do servidor e a voz.

## 5. Onde ficam as provas

- `$PROVAS/*.log`: a saída de cada comando.
- `$PROVAS/*.xcresult`: os resultados dos testes, com as capturas (abrir no Xcode). Exportar os anexos (Xcode 16 ou mais recente):

```sh
xcrun xcresulttool export attachments --path "$PROVAS/ui-simulado.xcresult" --output-path "$PROVAS/ui-simulado-anexos"
```

  Em versões mais antigas: abrir o `.xcresult` no Xcode, Report navigator, e exportar os anexos à mão.
- `$PROVAS/ui-simulado/*.png` e `$PROVAS/ui-real/*.png`: as capturas que o teste de interface escreve direto no Mac (`01_home_*`, `02_new_line`, `03_same_line_cached`, `04_subtitles_only`, `05_done`, `06_before_ok`, `07_after_ok`, `08_after_back`).
- O registo da app com cada resposta do tts (`voice`, `cached_rev`, `status`, `voice_status`, `interactions_spent`, `bytes`), no contentor da app e no registo do sistema:

```sh
cp "$(xcrun simctl get_app_container "$TV_UDID" com.oryksa.tvdemo data)/Library/Caches/ORYKSA_TV_DEMO.log" "$PROVAS/"
xcrun simctl spawn "$TV_UDID" log show --last 30m --info --predicate 'subsystem == "com.oryksa.tvdemo"' > "$PROVAS/demo-unified.log"
```

- `$PROVAS/live-*.txt`: o resumo do teste ao vivo.
- `$PROVAS/ui.mp4`: o vídeo.

Antes de entregar a pasta à MASTER, confirmar que o token não está em nenhum ficheiro (o `-f` lê o padrão do ficheiro, por isso o token não aparece no comando; só se mostram nomes de ficheiros):

```sh
grep -rlF -f ~/.oryksa/tv-test-token "$PROVAS" && echo "ATENÇÃO: token encontrado nestes ficheiros" || echo "token em nenhum ficheiro"
```

## 6. O que fica provado e o que NÃO fica

Se tudo passar, fica provado no simulador da Apple TV:
- que o pacote compila para tvOS, iOS e macOS;
- o contrato de cobrança da apresentadora com HTTP simulado (secção 2.2);
- com o teste ao vivo: a cobrança real das 3 falas e a voz guardada a tocar;
- com o teste de interface: o caminho pelo comando (fala nova, a mesma outra vez, só legendas) e, no simulado, o OK e o Voltar a calá-la sem passarem à app.

NÃO fica provado:
- numa Apple TV real (só simulador);
- o som e a qualidade da voz (o simulador toca no Mac; os testes usam um leitor falso);
- a página do telemóvel com um telemóvel real a ler o QR;
- o painel lateral transparente (precisa do tvOS 16.4 ou mais recente; antes aparece sobre fundo escuro);
- o tvOS 15, se esse runtime não estiver instalado no Mac;
- a revisão visual (tamanhos, foco, margens) por alguém a olhar para uma TV.
