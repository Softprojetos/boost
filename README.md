<div align="center">

# ⚡ Boost

### Otimizador de Windows 10 e 11 — num único comando

Mais FPS, menos telemetria, debloat de apps inúteis e limpeza.
**Tudo reversível, com ponto de restauração automático.**

[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?style=flat-square&logo=windows&logoColor=white)](https://boost-windows.com)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?style=flat-square&logo=powershell&logoColor=white)](https://boost.softprojetos.com)
[![Licença](https://img.shields.io/badge/licença-MIT-36F9A6?style=flat-square)](LICENSE)
[![Site](https://img.shields.io/badge/site-boost--windows.com-36F9A6?style=flat-square)](https://boost-windows.com)

</div>

---

## 🚀 Como usar

Abra o **PowerShell como Administrador** e cole:

```powershell
irm boost.softprojetos.com | iex
```

Dê Enter. A janela abre sozinha. Escolha os modos e ajustes que quiser — ou clique em **recomendados** — e aplique.

> 💡 **Quer ver o código antes de rodar?** É todo aberto. Leia o [`boost.ps1`](boost.ps1) aqui mesmo no GitHub, ou abra direto [boost.softprojetos.com](https://boost.softprojetos.com/) no navegador.

---

## ✨ O que ele faz

O Boost é dividido em **modos**. Cada ajuste usa API oficial do Windows e tem botão de desfazer individual.

### 🎮 Gamer
Tudo que importa pra FPS e input lag, ligado de uma vez:
- Plano de energia **Desempenho Máximo** (Ultimate Performance)
- **GPU Scheduling por hardware** (HAGS)
- **Game Mode** ligado, **Game DVR** desligado
- **Mouse 1:1** — desliga a aceleração do ponteiro (essencial pra mira)
- Libera a CPU reservada pra tarefas de fundo (SystemResponsiveness)
- Prioridade alta pros jogos (MMCSS) e Power Throttling desligado

### 🛡️ Privacidade
Corta a coleta de dados e a poluição da Microsoft:
- Desativa **telemetria** e o serviço DiagTrack
- Desliga o **ID de publicidade**
- Tira **sugestões** e apps instalados automaticamente
- Remove resultados da **web (Bing)** do menu Iniciar

### 🧹 Limpeza
Recupera espaço em segundos:
- Arquivos temporários (`%TEMP%` e `Windows\Temp`)
- Cache de DNS
- Lixeira (opcional)

### 📦 Apps Windows (debloat)
Remove os apps pré-instalados que ninguém pediu — Cortana, Copilot, Teams pessoal, Clipchamp, 3D Viewer e dezenas de outros. Marca o que é seguro remover e avisa em vermelho o que é arriscado (Loja, winget). Reinstala pela Store/winget quando quiser.

### ⚡ Apps úteis (winget)
Instala programas bons direto, sem caçar site de download — navegadores, players, dev tools, utilitários. Tudo via **winget oficial**, de fontes confiáveis. Detecta o que você já tem instalado.

### 🔄 Windows Update
Você no controle: liga, pausa ou adia as atualizações do jeito que preferir. Acaba com reinício no meio do jogo.

---

## 🔐 Segurança

A maioria dos "boosters" quebra o Windows e some. O Boost é o oposto:

- ✅ **Código 100% aberto** — leia antes de rodar, linha por linha
- ✅ Cria **ponto de restauração** automático antes de aplicar
- ✅ Cada tweak tem **botão de desfazer** individual
- ✅ Usa **APIs oficiais** do Windows, sem hacks no sistema
- ✅ **Zero** spyware, anúncio ou coleta de dados
- ✅ **Log completo** de tudo que foi feito em `%TEMP%\SoftProjetos-Boost`
- ✅ Nada de bypass de anti-cheat ou spoofer de HWID — **limpo**
- ✅ Funciona em **Windows 10 e 11**, Home e Pro

### ⚠️ Sobre alertas de antivírus

O Boost mexe em registro, desativa serviços e remove appx — exatamente o tipo de ação que antivírus marcam por heurística. **Isso é falso-positivo.** O código é aberto e auditável aqui no repositório. Se precisar, adicione uma exceção. Em caso de dúvida, leia o `boost.ps1` antes de rodar.

---

## 🤝 Contribuindo

Contribuições são bem-vindas! Seja um tweak novo, um app pro catálogo, correção de bug ou melhoria na UI.

1. Faça um fork do repositório
2. Crie uma branch (`git checkout -b meu-tweak`)
3. Faça suas mudanças no `boost.ps1`
4. Teste numa máquina Windows (de preferência numa VM)
5. Abra um Pull Request descrevendo o que mudou

Veja [CONTRIBUTING.md](CONTRIBUTING.md) para detalhes.

---

## ❓ FAQ

**Preciso baixar alguma coisa?**
Não. O comando `irm | iex` roda direto da web. Nada fica salvo no seu PC.

**É seguro?**
Sim. Tudo é reversível, cria ponto de restauração antes, e o código é aberto. Mas como qualquer ferramenta que mexe no sistema, leia o que vai aplicar e, idealmente, teste numa VM primeiro.

**Funciona offline?**
Não. Ele baixa o script e usa o winget (que precisa de internet pra instalar apps).

**Como desfaço um ajuste?**
Reabra o Boost e desligue o item — cada tweak tem revert próprio. Ou use o ponto de restauração criado automaticamente.

**Meu antivírus reclamou.**
Falso-positivo, comum em debloaters. O código é auditável aqui. Adicione exceção se precisar.

---

## 📜 Licença

Distribuído sob a licença **MIT**. Veja [LICENSE](LICENSE).

Em resumo: use, estude, modifique e compartilhe à vontade — só mantenha o aviso de copyright.

---

<div align="center">

Feito com ☕ por **[Soft Projetos](https://softprojetos.com)** · 🇧🇷 Brasil

[boost-windows.com](https://boost-windows.com) · [boost.softprojetos.com](https://boost.softprojetos.com)

</div>
