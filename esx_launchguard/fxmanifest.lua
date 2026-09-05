fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'esx_launchguard'
description 'Cancels modmenu launches so victims are not falsely flagged by the anticheat'
version '1.0.0'

shared_script 'config.lua'

client_scripts {
    'shared/detector.lua',
    'client/main.lua'
}

server_script 'server/main.lua'
