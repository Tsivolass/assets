fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'Cancels cheat launches that throw players into the air'
version '2.0.0'

shared_script 'config.lua'

client_scripts {
    'shared/detector.lua',
    'client/main.lua'
}
