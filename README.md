# CipherScanner

[![Version](https://img.shields.io/badge/version-12.0.0-blue.svg)](https://github.com/psycodeliccircus/CipherScanner/releases/tag/v12.0.0)  [![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

> Recurso para FiveM que analisa outros recursos em busca de padrões de código suspeitos e gera relatórios completos.

---

## 🗂 Sumário

- [✨ Destaques da Versão 12.0.0](#-destaques-da-versão-1200)  
- [📦 Arquitetura Modular](#-arquitetura-modular)  
- [🚀 Performance & Confiabilidade](#-performance--confiabilidade)  
- [📊 Histórico & Diff](#-histórico--diff)  
- [⚙ Comandos & Agendamento](#-comandos--agendamento)  
- [🔗 Integração com Discord Webhook](#-integração-com-discord-webhook)  
- [📄 Geração de Relatório](#-geração-de-relatório)  
- [⚙ Configuração (config.json)](#-configuração-configjson)  
- [📡 Eventos Emitidos](#-eventos-emitidos)  
- [📥 Instalação](#-instalação)  
- [🤝 Contribuição](#-contribuição)  
- [📝 Licença](#-licença)  

---

## ✨ Destaques da Versão 12.0.0

- Código **modularizado** em `utils.lua`, `scanner.lua`, `server.lua` e `server.js`.  
- **Incremental scan** usando cache para processar apenas arquivos modificados.  
- **Throttling** e **threads paralelas** para reduzir hitches e acelerar o processo.  
- Histórico de scans com **diff** automático e comandos dedicados.  
- Integração robusta com **Discord Webhook**, com payload adaptado para limites de caracteres.  
- **Checagem automática** de novas versões no GitHub Releases.  

---

## 📦 Arquitetura Modular

- **`utils.lua`**: JSON, logging, filtros, throttle e histórico.  
- **`scanner.lua`**: lógica de scan, cache, diff, report e webhook.  
- **`server.lua`**: comandos, checagem de update e scheduler.  
- **`server.js`**: exports seguros para leitura de diretórios e arquivos.  

---

## 🚀 Performance & Confiabilidade

- **Incremental Scanning**: somente arquivos alterados são reprocessados.  
- **Throttling**: evita travamentos limitando operações por frame.  
- **Multi-threading**: cada recurso é escaneado em thread separada.  
- **Filtros** configuráveis para extensões e diretórios a ignorar.  

---

## 📊 Histórico & Diff

- Armazena até `historyLimit` scans em `cipher_history.json`.  
- Comando `/cipherscan diff <resource>` para comparar últimos dois scans.  
- Evento `cipher:diff` disparado automaticamente se houver mudanças.  
- Comando `/cipherscan clearhistory [resource]` para limpar histórico.  

---

## ⚙ Comandos & Agendamento

- **`/cipherscan start [resource]`**: inicia scan completo ou de recurso específico.  
- **`/cipherscan update`**: checa GitHub para novas versões (evento `cipher:updateAvailable`).  
- **`/cipherscan diff <resource>`**, **`/cipherscan clearhistory [res]`**, **`/cipherscan pause`**, **`/cipherscan resume`**.  
- Agendamento via `autoOnStart` e `autoInterval` em `config.json`.  

---

## 🔗 Integração com Discord Webhook

- Configurável em `config.json`: `webhook.enabled`, `webhook.url`.  
- Payload inteligente: utiliza `description` para resumo e lista hits não-zero.  
- Logs de debug mostram payload e resposta da API Discord.  

---

## 📄 Geração de Relatório

- Arquivo `report.md` com tabela de recursos, arquivos processados, hits e tempo.  
- Atualizável após cada scan.  

---

## ⚙ Configuração (config.json)

Personalize comportamentos principais:

\`\`\`json
{
  "version": "12.0.0",
  "signatures": [...],
  "incremental": true,
  "maxOpsPerFrame": 30,
  "historyLimit": 5,
  "autoOnStart": true,
  "autoInterval": 3600000,
  "update": { "enabled": true, ... },
  "webhook": { "enabled": true, "url": "<seu_webhook>" }
}
\`\`\`

---

## 📡 Eventos Emitidos

- \`cipher:resourceScanned\`: stats de cada recurso.  
- \`cipher:scanComplete\`: stats gerais ao final.  
- \`cipher:diff\`: diff de mudanças.  
- \`cipher:updateAvailable\`: nova versão disponível.  

---

## 📥 Instalação

1. Clone este repositório em \`resources/CipherScanner\`.  
2. Adicione \`start CipherScanner\` em \`server.cfg\`.  
3. Ajuste \`config.json\` conforme necessário.  
4. Execute \`refresh\` e \`start CipherScanner\`.  

---

## 🤝 Contribuição

Pull requests são bem-vindos! Veja as [issues](https://github.com/psycodeliccircus/CipherScanner/issues) e o [contributing guide](CONTRIBUTING.md).  

---

## 📝 Licença

Este projeto é distribuído sob a licença [MIT](LICENSE).
