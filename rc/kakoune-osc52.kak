declare-option -docstring 'multiple selections copy to clipboard feature' \
    bool osc52_sync_multiple_selections false

declare-option -docstring 'maximum time to wait for paste response from terminal' \
    int osc52_sync_paste_timeout 5

declare-option -hidden str osc52_sync_paste_buffer ""
declare-option -hidden bool osc52_sync_paste_pending false
declare-option -hidden bool osc52_sync_deferred false

define-command osc52-sync-set -docstring 'set system clipboard from the " register' %{
    nop %sh{
        if [ "$kak_opt_osc52_sync_multiple_selections" = 'true' ]; then
            clipboard="$kak_reg_dquote"
        else
            clipboard="$kak_main_reg_dquote"
        fi
        
        encoded=$(printf '%s' "$clipboard" | base64 | tr -d '\n')
        printf '\033]52;c;%s\a' "$encoded" >/dev/tty
    }
}

define-command -hidden osc52-sync-install-paste-mappings -docstring "install mappings to parse OSC 52 response"%(
    map window prompt '<a-\>' '}<ret>'
    map window prompt %sh{printf '\a'} '}<ret>'
    map window normal '<a-]>' ': osc52-sync-capture %{'
)

define-command -hidden osc52-sync-uninstall-paste-mappings -docstring "clean up the mappings" %(
    unmap window prompt '<a-\>' '}<ret>'
    unmap window prompt %sh{printf '\a'} '}<ret>'
    unmap window normal '<a-]>' ': osc52-sync-capture %{'
)

define-command -hidden -params 1 osc52-sync-paste-recv %{
    set-option window osc52_sync_paste_buffer %sh{ 
        printf '%s' "$kak_opt_osc52_sync_paste_buffer$1" 
    }

    set-register dquote %opt{osc52_sync_paste_buffer}
    set-option window osc52_sync_paste_pending false
}

define-command -hidden -params 1 osc52-sync-capture %{
    nop %sh{ {
        # clean up mappings after the timeout
        (
            sleep "$kak_opt_osc52_sync_paste_timeout"
            printf 'eval -client %%{%s} %%{%s}\n' \
                "$kak_client" 'osc52-sync-uninstall-paste-mappings; set-option window osc52_sync_paste_pending false' |
                kak -p "$kak_session"
        ) &
        
        # process OSC 52 response
        osc52() {
            decoded=$(printf '%s' "$1" | base64 --decode)
            quoted_decoded=$(printf '%s' "$decoded" | sed "s/'/''''/g")
            printf "eval -client '%s' 'osc52-sync-paste-recv ''%s'''\n" \
                "$kak_client" "$quoted_decoded" |
                kak -p "$kak_session"
        }
        
        oscmsg=$1
        case "$oscmsg" in
        '52;'*) 
            osc52 "${oscmsg#52;*;}"
            ;;
        esac
    } >/dev/null 2>&1 </dev/null & }
}

define-command osc52-sync-get -docstring 'get system clipboard into the " register' %{
    evaluate-commands %sh{
        if [ "$kak_opt_osc52_sync_paste_pending" = "true" ]; then
            exit 0
        fi
        printf 'nop'
    }
    
    set-option window osc52_sync_paste_pending true
    set-option window osc52_sync_paste_buffer ""
    osc52-sync-install-paste-mappings
    
    nop %sh{
        printf '\033]52;c;?\a' >/dev/tty
    }
}

define-command -hidden osc52-sync-get-deferred -docstring "set a reminder to get clipboard" %{
    set-option window osc52_sync_deferred true
}

define-command -hidden osc52-sync-check-deferred -docstring "if the reminder is set, get the clipboard" %{
    evaluate-commands %sh{
        if [ "$kak_opt_osc52_sync_deferred" = "true" ]; then
            printf 'set-option window osc52_sync_deferred false; osc52-sync-get'
        fi
    }
}

define-command osc52-sync-enable -docstring 'enable OSC 52 clipboard integration' %{
    hook -group 'osc52-sync' global WinCreate .* %{ osc52-sync-get }
    hook -group 'osc52-sync' global FocusIn .* %{ osc52-sync-get-deferred }
    hook -group 'osc52-sync' global NormalIdle .* %{ osc52-sync-check-deferred }
    hook -group 'osc52-sync' global RegisterModified \" %{ osc52-sync-set }
}

define-command osc52-sync-disable -docstring 'disable OSC 52 clipboard integration' %{
    remove-hooks global 'osc52-sync'
    osc52-sync-uninstall-paste-mappings
}
