fx_version 'cerulean'
game 'gta5'

author 'psycodeliccircus'
description 'CipherScanner v11 – scanner modularizado'
version '11.0.0'

server_scripts {
    'server.js',
    'scanAll.lua',   -- agora carregamos o módulo de scan primeiro
    'server.lua',    -- depois o core: update checker & comandos
}

files {
    'config.json',
    'cipher_cache.json',
    'cipher_results.json',
    'report.md',
}
