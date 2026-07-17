# Claude Usage Bar

Um app de barra de menu para macOS que mostra quanto do seu plano do **Claude Code**
já foi usado — janela de sessão (5h) e semanal (7d) — com contagem regressiva até o
reset. Usa a mesma conta autenticada no Claude Code (lê as credenciais OAuth do
Keychain) e consulta o mesmo endpoint que alimenta o comando `/usage`.

```
Barra de menu:   ◐ 23% · zera em 4h21m

Painel (ao clicar):
  Claude Code · Plano Max (20x)
  Sessão (5h)   ▓▓░░░░░░░░  23%   zera 07:20 · em 4h21m
  Semana (7d)   ▓▓▓░░░░░░░  25%   zera 22/07 03:00 · em 4d19h
  Atualizado agora · ↻ Atualizar · Iniciar no login · Sair
```

A cor do texto na barra indica o nível: **normal** até 70%, **amarelo** 70–90%,
**vermelho** acima de 90% (ou quando a API sinaliza que você está no teto).

---

## Requisitos

- **macOS 13+** (Ventura ou mais novo).
- **Swift toolchain** — basta o Command Line Tools (`xcode-select --install`).
  **Não precisa do Xcode completo.**
- Estar **logado no Claude Code** (o app lê o item `Claude Code-credentials` do
  Keychain, criado quando você faz login no Claude Code).

Confirme o toolchain:

```bash
swift --version   # deve mostrar Swift 6.x
```

---

## Como rodar

### Instalar e iniciar (recomendado)

```bash
./Scripts/make-app.sh --install
```

Isso compila em release, monta o `.app`, **encerra qualquer cópia rodando**,
instala em `/Applications/ClaudeUsageBar.app` e reabre. É o comando único para o
dia a dia — sempre que mudar o código, rode isso de novo para atualizar.

### Primeira execução: permissão do Keychain

Na primeira vez que o app lê suas credenciais, o macOS mostra um prompt do tipo:

> *"ClaudeUsageBar quer usar informações confidenciais armazenadas em
> 'Claude Code-credentials' no seu keychain."*

Clique em **"Sempre Permitir"** (Always Allow). Isso é esperado — o app é um
binário diferente do Claude Code, então o macOS pede autorização uma única vez.
Depois disso ele nunca mais pergunta.

- Enquanto o prompt não é aprovado, a barra fica em `◐ …`.
- Se aparecer `◐ —`, o app não encontrou credenciais → verifique se está logado
  no Claude Code.

### Iniciar junto com o Mac

O "Iniciar no login" já vem **ligado por padrão** na primeira execução. Para
funcionar de forma persistente (sobreviver a reboot, aparecer em
*Ajustes do Sistema → Geral → Itens de início de sessão*), o app precisa estar em
`/Applications` — o que o `--install` já garante. Você pode ligar/desligar isso a
qualquer momento pelo item **"Iniciar no login"** no painel.

---

## Outros modos do script

| Comando | O que faz |
|---|---|
| `./Scripts/make-app.sh` | Só compila e monta o bundle em `./build`. Não instala nem abre. |
| `./Scripts/make-app.sh --run` | Compila, encerra a cópia rodando e reabre a partir de `./build` (sem tocar em `/Applications`). Bom para testar rápido. |
| `./Scripts/make-app.sh --install` | Fluxo completo: compila, encerra, instala em `/Applications` e reabre. |

Para encerrar o app manualmente: clique em **Sair** no painel, ou:

```bash
osascript -e 'quit app "ClaudeUsageBar"'
```

---

## Fluxo de atualização

**Dados (automático, em runtime):**

- Atualiza a cada **60 segundos**.
- **↻ Atualizar** (ou `⌘R` com o painel aberto) força na hora.
- **Token expirado** → renova sozinho pelo `refreshToken` e regrava no Keychain,
  preservando todos os outros dados do item (inclusive tokens de MCP).
- **Sem internet / API fora** → mantém o último valor e mostra
  "⚠ desatualizado há X min"; recupera sozinho no próximo ciclo.

**App (quando o código muda):** rode `./Scripts/make-app.sh --install` de novo.
Ainda não há auto-update (tipo Sparkle) — a atualização é manual por esse comando.

---

## Testes

A lógica central mora na biblioteca `UsageKit` e é totalmente testada. Como
XCTest/swift-testing só vêm com o Xcode completo, os testes rodam por um pequeno
runner próprio (um executável), sem depender do Xcode:

```bash
swift run UsageKitTests
```

Saída esperada: `✓ All N checks passed` (exit code 0 em sucesso, 1 em falha —
serve para CI).

---

## Arquitetura

Duas camadas, separadas de propósito para permitir evoluir para um widget nativo
(WidgetKit) no futuro — toda a lógica testável fica em `UsageKit`, sem nenhum
`import AppKit`.

```
Sources/
  UsageKit/                     ← biblioteca reutilizável (sem UI, testada)
    Keychain.swift              leitura/escrita do item do Keychain (SecItem)
    CredentialsBlob.swift       parse + reescrita não-destrutiva do JSON de credenciais
    KeychainStore.swift         compõe os dois acima (CredentialsStoring)
    Credentials.swift           modelo de credenciais + rótulo do plano ("Max (20x)")
    TokenProvider.swift         decide expiração + renova o token (behind protocol)
    OAuthRefresher.swift        chamada real ao endpoint de refresh OAuth
    HTTPClient.swift            protocolo HTTP + implementação URLSession
    UsageClient.swift           busca GET /oauth/usage → UsageSnapshot
    UsageResponse.swift         DTOs Decodable da resposta da API
    UsageSnapshot.swift         modelo normalizado (sessão, semana, por modelo)
    TimeFormatting.swift        contagem regressiva, tempo relativo, horário
    MenuBarTitle.swift          renderização pura do texto da barra (testada)
  ClaudeUsageBar/               ← app AppKit fino (barra de menu)
    main.swift                  bootstrap do NSApplication (accessory / sem Dock)
    AppDelegate.swift           status item, poller de 60s, estados, wiring
    UsagePanelView.swift        painel com barras de progresso e resets
    LoginItem.swift             iniciar no login via SMAppService
Tests/UsageKitTests/            ← runner de testes próprio + fixtures
Packaging/Info.plist            ← template do bundle (LSUIElement = sem Dock)
Scripts/make-app.sh             ← build / --run / --install
docs/superpowers/               ← spec de design e plano de implementação
```

### Como os dados chegam na tela

1. `KeychainStore` lê `Claude Code-credentials` e decodifica em `Credentials`.
2. `TokenProvider` verifica a validade; se expirado, `OAuthRefresher` renova e
   `KeychainStore` regrava (sem apagar outros campos do item).
3. `UsageClient` chama `GET https://api.anthropic.com/api/oauth/usage` com o token
   e mapeia a resposta em `UsageSnapshot`.
4. `renderMenuBarTitle` transforma o snapshot no texto da barra; `UsagePanel`
   monta o painel. O `AppDelegate` refaz isso a cada 60s.

---

## Solução de problemas

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| Barra travada em `◐ …` | Prompt do Keychain não aprovado, ou sem rede | Aprove o prompt ("Sempre Permitir"); confira a internet |
| `◐ —` | App não achou credenciais | Faça login no Claude Code e clique em ↻ Atualizar |
| "⚠ desatualizado há X min" no painel | Rede/API indisponível | Normal; recupera sozinho. Force com ↻ Atualizar |
| "Iniciar no login" não persiste | App não está em `/Applications` | Rode `./Scripts/make-app.sh --install` |
| Nada aparece na barra | App não subiu | `pgrep -lf ClaudeUsageBar`; se vazio, rode o `--install` |

---

## Notas técnicas

- **Endpoint de uso:** `GET https://api.anthropic.com/api/oauth/usage`
  (headers `Authorization: Bearer <token>` e `anthropic-beta: oauth-2025-04-20`).
- **Refresh OAuth:** `POST https://console.anthropic.com/v1/oauth/token`
  (`grant_type=refresh_token`). Fica atrás de um protocolo e é acionado só quando
  o token expira.
- **Keychain:** o item é um *generic password* de serviço `Claude Code-credentials`.
  Na escrita de tokens renovados, só os campos `accessToken`/`refreshToken`/
  `expiresAt` dentro de `claudeAiOauth` são alterados — o resto (ex.: `mcpOAuth`)
  é preservado.
- O bundle é assinado ad-hoc (`codesign --sign -`) para o `SMAppService` e as ACLs
  do Keychain se comportarem de forma previsível.
