fx_version 'cerulean'
game 'gta5'

author 'RenildoMarcio'
description 'CipherScanner v8 – scanner incremental e dinâmico de cipher patterns'
version '8.0.0'

server_scripts {
    'server.js',
    'server.lua',
}

files {
    'config.json',
    'cipher_cache.json',
    'cipher_results.json',
}

-- Se você quiser dar permissão ACE para rodar /cipherscan:
-- add_ace group.admin cipherscanner.command allow
