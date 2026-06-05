# Contribuindo com o Boost

Obrigado por querer ajudar! Este guia explica como contribuir de forma que sua mudança seja aceita rápido.

## Filosofia do projeto

- **Tudo reversível.** Todo tweak que aplica algo precisa ter um `Revert` que desfaz. Sem exceção.
- **APIs oficiais, sem gambiarra.** Use os caminhos documentados do Windows (registro, `SystemParametersInfo`, `powercfg`, `winget`...). Nada de hack obscuro que quebra no próximo update.
- **Nada de risco ao usuário.** Zero spoofer de HWID, zero bypass de anti-cheat, zero coleta de dados. Isso é regra absoluta — PRs nesse sentido são recusados na hora.
- **Curadoria > quantidade.** Não queremos uma "app store". Cada item novo precisa fazer sentido pra maioria dos usuários.
- **Sempre em português** nos textos visíveis ao usuário (nomes, descrições, status).

## Estrutura

Tudo vive em **`boost.ps1`** (arquivo único, servido direto). Os tweaks são objetos `[pscustomobject]` com este formato:

```powershell
[pscustomobject]@{
  Id='meu-tweak'                      # identificador único
  Cat='Desempenho & Jogos'           # categoria (= modo da UI)
  Name='Nome curto do ajuste'
  Default=$true                       # vem marcado em "recomendados"?
  Reboot=$false                       # exige reiniciar?
  Desc='Explicação clara do que faz e do impacto.'
  Apply={ param($t) <# aplica #> }
  Revert={ param($t) <# desfaz #> }
  Test={ param($t) <# retorna $true se já está aplicado #> }
}
```

Para **apps de debloat**, adicione uma entrada no array `$apps` (com `Pkg`, `Store`, `Rec`, `D`).
Para **apps do winget**, adicione no array `$externalApps` (com `N`, `G`, `W`).

## Passo a passo

1. Faça um **fork** do repositório
2. Crie uma branch descritiva: `git checkout -b tweak-desativar-xbox-overlay`
3. Faça a mudança no `boost.ps1`
4. **Teste numa VM Windows** (10 e 11 se possível). Confirme que:
   - O `Apply` faz o que promete
   - O `Revert` desfaz de verdade
   - O `Test` reflete o estado certo
   - A UI não quebra (a janela abre, o item aparece no modo certo)
5. Valide a sintaxe: o script precisa passar no parser do PowerShell sem erros
6. Abra um **Pull Request** explicando o que mudou e por quê

## Checklist do PR

- [ ] O tweak é reversível (`Apply` ↔ `Revert`)
- [ ] Usa API oficial, sem hack
- [ ] Testado em VM (diga qual versão do Windows)
- [ ] Descrição (`Desc`) clara, em português
- [ ] Nada de spoofer/bypass/coleta de dados
- [ ] Sintaxe validada (sem erros de parse)

## Dúvidas

Abra uma **Issue** descrevendo a ideia antes de codar, se for uma mudança grande. Assim a gente alinha antes de você gastar tempo.
