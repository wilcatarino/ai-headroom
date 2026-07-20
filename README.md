# AI Headroom

AI Headroom é um app de barra de menu para macOS que mostra, de relance, quanto dos limites das suas ferramentas de IA ainda resta. Ele começa com o Claude Code e foi desenhado para receber outros provedores depois.

Para o Claude Code, mostra quanto do plano já foi usado, com contagem regressiva até o reset: janela de sessão (5h) e janela semanal (7d). Usa a conta já autenticada no Claude Code (lê as credenciais OAuth do Keychain) e consulta o mesmo endpoint que alimenta o comando `/usage`.

```
Barra de menu:   ◐ 23% · zera em 4h21m

Painel (ao clicar):
  Claude Code · Plano Max (20x)
  Sessão (5h)   ▓▓░░░░░░░░  23%   zera 07:20 · em 4h21m
  Semana (7d)   ▓▓▓░░░░░░░  25%   zera 22/07 03:00 · em 4d19h
  Atualizado agora · Atualizar · Iniciar no login · Sair
```

A cor do texto na barra indica o nível: normal até 70%, laranja de 70% a 90% e vermelho acima de 90% (ou quando a API sinaliza que você atingiu o teto).

## Aviso

Projeto independente, sem vínculo com a Anthropic. Ele lê as credenciais que o Claude Code já guardou no seu Keychain e consulta um endpoint de uso não documentado, que pode mudar ou sair do ar sem aviso. As credenciais são usadas apenas localmente, para chamar a própria API da Anthropic, e não são enviadas a nenhum outro lugar nem gravadas no repositório. Use por sua conta e risco.

## Requisitos

- macOS 13 (Ventura) ou mais novo.
- Swift toolchain via Command Line Tools (`xcode-select --install`). Não é necessário o Xcode completo.
- Estar logado no Claude Code. O app lê o item `Claude Code-credentials` do Keychain, criado quando você faz login no Claude Code.

Confirme o toolchain com `swift --version` (deve mostrar Swift 6.x).

## Como rodar

### Instalar pela última release (mais fácil)

Baixe o `AI-Headroom-*.zip` da [página de Releases](https://github.com/wilcatarino/ai-headroom/releases), descompacte e mova `AI Headroom.app` para a pasta Aplicativos. Como o app não é assinado por um Developer ID da Apple nem notarizado, na primeira abertura o macOS bloqueia. Para liberar, escolha uma das opções:

- Em Ajustes do Sistema, Privacidade e Segurança, role até a mensagem sobre "AI Headroom" e clique em "Abrir Mesmo Assim".
- Ou no Terminal: `xattr -dr com.apple.quarantine "/Applications/AI Headroom.app"`, depois abra o app.

### Compilar do código

Compilar, instalar em `/Applications` e abrir:

```bash
./Scripts/make-app.sh --install
```

Esse é o comando do dia a dia. Sempre que o código mudar, rode de novo para atualizar a versão em execução.

### Primeira execução: permissão do Keychain

Na primeira vez que o app lê suas credenciais, o macOS mostra um prompt parecido com este:

> "AI Headroom quer usar informações confidenciais armazenadas em 'Claude Code-credentials' no seu keychain."

Clique em "Sempre Permitir". O app é um binário diferente do Claude Code, então o macOS pede autorização. Estados possíveis na barra enquanto isso:

- `◐ …`: carregando (prompt ainda não aprovado, ou primeira busca em andamento).
- `◐ ⚠`: a última busca falhou (rede, API ou Keychain). O app tenta de novo sozinho com backoff de 2, 4, 8 e 15 segundos até a primeira carga dar certo. Você também pode forçar pelo item Atualizar.
- `◐ -`: nenhuma credencial encontrada. Verifique se está logado no Claude Code.

Cada `--install` re-assina o app (ad-hoc), então o macOS pode pedir a permissão do Keychain novamente após uma atualização. Aprove uma vez e o app se recupera sozinho.

### Iniciar junto com o Mac

A opção "Iniciar no login" vem ligada por padrão na primeira execução. Para valer de forma persistente (sobreviver a reboot e aparecer em Ajustes do Sistema > Geral > Itens de início de sessão), o app precisa estar em `/Applications`, o que o `--install` já garante. Dá para ligar ou desligar isso a qualquer momento pelo item "Iniciar no login" no painel.

## Modos do script de build

| Comando | O que faz |
|---|---|
| `./Scripts/make-app.sh` | Compila e monta o bundle em `./build`. Não instala nem abre. |
| `./Scripts/make-app.sh --run` | Compila, encerra a cópia rodando e reabre a partir de `./build`, sem tocar em `/Applications`. |
| `./Scripts/make-app.sh --install` | Compila, encerra, instala em `/Applications` e reabre. |

Para encerrar o app manualmente, use o item Sair no painel ou rode `osascript -e 'quit app "AI Headroom"'`.

## Atualização dos dados

Em runtime, o app cuida da atualização sozinho:

- Busca a cada 60 segundos.
- O item Atualizar (ou `Cmd-R` com o painel aberto) força uma busca imediata.
- Quando o token expira, o app renova pelo `refreshToken` e regrava no Keychain, preservando os demais campos do item (inclusive tokens de MCP).
- Sem rede ou com a API fora do ar, mantém o último valor e mostra "desatualizado há X min", recuperando no ciclo seguinte.

Não há auto-update do próprio app. Para atualizar o binário, rode o `--install`.

## Testes

A lógica central fica na biblioteca `UsageKit` e é coberta por testes. Como XCTest e swift-testing só acompanham o Xcode completo, os testes rodam por um runner próprio (um executável), sem depender do Xcode:

```bash
swift run UsageKitTests
```

A saída esperada é `✓ All N checks passed`. O processo sai com código 0 em sucesso e 1 em falha, o que serve para CI.

## Arquitetura

Duas camadas. Toda a lógica testável fica em `UsageKit`, sem nenhum `import AppKit`, o que mantém a porta aberta para um widget nativo (WidgetKit) no futuro reaproveitando a mesma biblioteca.

```
Sources/
  UsageKit/                     biblioteca reutilizável (sem UI, testada)
    Keychain.swift              leitura e escrita do item do Keychain (SecItem)
    CredentialsBlob.swift       parse e reescrita não destrutiva do JSON de credenciais
    KeychainStore.swift         compõe os dois acima (CredentialsStoring)
    Credentials.swift           modelo de credenciais e rótulo do plano
    TokenProvider.swift         decide expiração e renova o token (via protocolo)
    OAuthRefresher.swift        chamada real ao endpoint de refresh OAuth
    HTTPClient.swift            protocolo HTTP e implementação com URLSession
    UsageClient.swift           busca GET /oauth/usage e devolve UsageSnapshot
    UsageResponse.swift         DTOs Decodable da resposta da API
    UsageSnapshot.swift         modelo normalizado (sessão, semana, por modelo)
    TimeFormatting.swift        contagem regressiva, tempo relativo e horário
    MenuBarTitle.swift          renderização pura do texto da barra (testada)
  AIHeadroom/             app AppKit fino (barra de menu)
    main.swift                  bootstrap do NSApplication (accessory, sem Dock)
    AppDelegate.swift           status item, poller de 60s, estados e wiring
    UsagePanelView.swift        painel com barras de progresso e resets
    LoginItem.swift             iniciar no login via SMAppService
Tests/UsageKitTests/            runner de testes próprio e fixtures
Packaging/Info.plist            template do bundle (LSUIElement = sem Dock)
Scripts/make-app.sh             build, run e install
docs/design/                    spec de design e plano de implementação (histórico)
```

Fluxo dos dados até a tela:

1. `KeychainStore` lê `Claude Code-credentials` e decodifica em `Credentials`.
2. `TokenProvider` verifica a validade. Se expirado, `OAuthRefresher` renova e `KeychainStore` regrava sem apagar outros campos do item.
3. `UsageClient` chama `GET https://api.anthropic.com/api/oauth/usage` com o token e mapeia a resposta em `UsageSnapshot`.
4. `renderMenuBarTitle` transforma o snapshot no texto da barra e `UsagePanel` monta o painel. O `AppDelegate` repete isso a cada 60 segundos.

## Solução de problemas

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| Barra parada em `◐ …` | Prompt do Keychain não aprovado, ou sem rede | Aprove o prompt e confira a internet |
| `◐ ⚠` | Falha na busca (rede, API ou Keychain) | Recupera sozinho com retry, ou use Atualizar |
| `◐ -` | App não achou credenciais | Faça login no Claude Code e use Atualizar |
| "desatualizado há X min" no painel | Rede ou API indisponível | Normal, recupera sozinho no próximo ciclo |
| "Iniciar no login" não persiste | App não está em `/Applications` | Rode `./Scripts/make-app.sh --install` |
| Nada aparece na barra | App não subiu | `pgrep -lf AIHeadroom` e, se vazio, rode o `--install` |

### Aparece como "Desenvolvedor desconhecido"

Em Ajustes do Sistema, na tela de Geral, em Itens de Início e Extensões, o AI Headroom aparece com o nome correto, mas agrupado embaixo de "Desenvolvedor desconhecido". O nome do app não está errado. O que fica desconhecido é o desenvolvedor, porque o bundle é assinado ad-hoc (`codesign --sign -`), sem um Team ID nem um Developer Name. Este projeto não tem hoje um Developer ID da Apple, então esse agrupamento é esperado e inofensivo. A única forma de sair do grupo "desconhecido" e remover o aviso do Gatekeeper na primeira abertura é assinar com um certificado Developer ID Application e notarizar o app, o que exige uma conta paga do Apple Developer Program. Enquanto essa conta não existir, o comportamento continua o descrito aqui.

Para ver logs de diagnóstico, abra o Console.app e filtre por `AIHeadroom`, ou rode o binário direto e observe o stderr:

```bash
swift run -c release AIHeadroom   # Ctrl-C para sair
```

## Notas técnicas

- Endpoint de uso: `GET https://api.anthropic.com/api/oauth/usage`, com os headers `Authorization: Bearer <token>` e `anthropic-beta: oauth-2025-04-20`.
- Refresh OAuth: `POST https://console.anthropic.com/v1/oauth/token` com `grant_type=refresh_token`. Fica atrás de um protocolo e roda só quando o token expira.
- Keychain: o item é um generic password de serviço `Claude Code-credentials`. Ao gravar tokens renovados, apenas `accessToken`, `refreshToken` e `expiresAt` dentro de `claudeAiOauth` são alterados. O resto do item, como `mcpOAuth`, é preservado.
- O bundle é assinado ad-hoc (`codesign --sign -`) para o `SMAppService` e as ACLs do Keychain se comportarem de forma previsível. Sem um Developer ID da Apple, o app não tem Team ID, então o macOS o lista como "Desenvolvedor desconhecido".
