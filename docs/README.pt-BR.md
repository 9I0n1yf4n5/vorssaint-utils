# Vorssaint Utils

> Uma central de utilidades premium e nativa para macOS — vivendo discretamente na barra de menus.

*Read in [English](../README.md).*

O Vorssaint Utils mantém o Mac acordado sob demanda, mostra as leituras do
sistema que realmente importam, dá ao mouse a rolagem estilo Windows sem mexer
no trackpad e substitui o ⌘Tab por um alternador de janelas com miniaturas
reais. 100% nativo (SwiftUI + AppKit), bilíngue (pt-BR / en-US), sem Electron,
sem analytics, sem chamadas de rede.

## Recursos

### ⚡ Manter acordado
- Liga/desliga pelo painel, pelo menu de clique direito ou pelo atalho global **⌃⌥⌘K**
- Sessões de 15 min a 8 h, ou indefinidas — com extensões de +15/+30/+60 min
- Mantenha a tela ligada, ou deixe-a apagar com o sistema acordado
- **Tampa fechada**: MacBook ativo mesmo fechado (`pmset disablesleep`,
  revertido automaticamente ao fim da sessão, ao sair do app e após quedas)
- **Sem senha (opcional)**: regra `sudoers` restrita a `pmset disablesleep 0/1`,
  validada com `visudo -c`, removível a qualquer momento
- **Proteção de bateria**: a sessão desliga abaixo de um limite de carga
- Contagem regressiva na barra de menus e notificações de fim de sessão

### 🌡️ Monitor do sistema
- **Temperaturas** de CPU, GPU e bateria — a leitura mais relevante de cada
  componente, direto do SMC
- **Uso de hardware**: % de CPU e % de GPU
- **Pressão de memória** com indicador semáforo
  (verde = normal, amarelo = atenção, vermelho = crítico) e memória em uso/total

### 🖱️ Rolagem estilo Windows
- Inverte **apenas a roda do mouse** — o trackpad continua com a rolagem natural
- Vale na hora, sem reiniciar, sem extensão de kernel

### 🪟 Alternador de janelas
- Substitui o **⌘Tab** por uma grade com cada janela em miniatura ao vivo —
  não apenas ícones
- Várias janelas do mesmo app aparecem individualmente
- Segure ⌘ e toque Tab para navegar; Shift/← volta; solte para trocar; **Q**
  fecha o app selecionado; Esc cancela — segue a ordem real de uso recente,
  fluido, animado, compatível com Mission Control e Spaces
- Sem a Gravação de Tela, degrada graciosamente para ícones

### 🧰 Utilidades
- Ocultar ícones da mesa (apresentações, gravações)
- Mostrar arquivos ocultos no Finder
- Desligar a tela · Ejetar todos os discos · Esvaziar Lixeira (com confirmação)

## Instalação

### Download (recomendado)
Baixe o DMG mais recente em [**Releases**](https://github.com/vorssaint/vorssaint-utils/releases),
abra e arraste o **Vorssaint Utils** para **Aplicativos**.

> As releases têm assinatura ad-hoc (sem certificado pago da Apple). Na
> primeira abertura, clique direito no app → **Abrir**, ou remova a quarentena:
> `xattr -d com.apple.quarantine "/Applications/Vorssaint Utils.app"`

### Compilar do código
```sh
git clone https://github.com/vorssaint/vorssaint-utils.git
cd vorssaint-utils
./build.sh            # compila, gera o ícone e monta o bundle assinado
./build.sh --install  # idem + instala em /Aplicativos e abre
```

### Requisitos
- macOS 14 (Sonoma) ou mais recente
- Apple Silicon
- Xcode Command Line Tools (para compilar)

## Permissões

Tudo é opcional — os recursos degradam graciosamente e o onboarding guia cada
concessão:

| Permissão | Usada por | Sem ela |
|---|---|---|
| **Acessibilidade** | Inversor de rolagem, teclado do alternador | Os dois recursos ficam desligados |
| **Gravação de Tela** | Títulos e miniaturas no alternador | Alternador mostra só ícones |
| **Notificações** | Avisos de fim de sessão e proteção de bateria | Operação silenciosa |
| **Administrador (uma vez, opcional)** | Tampa fechada sem senha | Pede senha a cada uso |

A primeira abertura traz um onboarding em 7 etapas (idioma, permissões, tour
do monitor, recursos opcionais, verificação). Revise quando quiser em
**Ajustes › Sobre › Rever introdução**.

## Licença

[PolyForm Noncommercial License 1.0.0](../LICENSE) — © 2026 Vorssaint.
Livre para usar, modificar e compartilhar para qualquer fim **não comercial**,
com atribuição. Uso comercial não é permitido.
