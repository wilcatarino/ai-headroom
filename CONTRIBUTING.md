# Contribuindo

## Ambiente

- macOS 13 ou mais novo.
- Swift toolchain via Command Line Tools (`xcode-select --install`). O Xcode completo não é necessário.

## Fluxo

1. Crie um branch a partir de `main`.
2. Rode os testes antes de abrir o PR:

   ```bash
   swift build
   swift run UsageKitTests
   ```

3. A CI executa build, testes e a montagem do bundle a cada push e PR.

## Organização do código

- Toda lógica testável vive em `Sources/UsageKit` e não importa AppKit.
- A camada de UI (`Sources/ClaudeUsageBar`) é fina: status item, painel e wiring.
- Dependências de rede, Keychain e relógio ficam atrás de protocolos, o que permite testar com fakes. Veja `Tests/UsageKitTests`.

## Testes

Os testes usam um runner próprio (executável), porque XCTest e swift-testing só acompanham o Xcode completo. Para adicionar um teste, escreva uma função em `Tests/UsageKitTests` e registre a chamada em `main.swift`.

## Preview de cores e estados

Para revisar as cores de severidade (warning, critical) sem esperar o uso real subir, rode o binário direto com a variável `CUB_PREVIEW`, que força um estado e pula a busca ao vivo:

```bash
CUB_PREVIEW=warning "$(swift build --show-bin-path)/ClaudeUsageBar"
CUB_PREVIEW=critical "$(swift build --show-bin-path)/ClaudeUsageBar"
```

As cores ficam centralizadas em `Sources/ClaudeUsageBar/Palette.swift`. Observação: o `open` do macOS não repassa variáveis de ambiente para o app, por isso o preview roda o binário direto.

## Segurança

Nunca faça commit de tokens reais. As fixtures usam apenas placeholders (`sk-ant-oat01-OLD`). O app lê credenciais do Keychain em runtime e nada é persistido no repositório.
