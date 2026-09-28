# Directory bookmarks: `hash -d` named dirs + `cd && ls` aliases.
# File bookmarks: open in $EDITOR.

hash -d cf=~/.config
hash -d cfmj=~/.config/manjaro-setup
hash -d dc=~/Documents
hash -d dw=~/Downloads
hash -d lbin=~/.local/bin
hash -d lcar=~/.local/care
hash -d lshr=~/.local/share
hash -d mu=~/Music
hash -d sem=~/Documents/uni/SoSe26
hash -d uni=~/Documents/uni

alias -- cf='cd ~/.config && ls'
alias -- cfmj='cd ~/.config/manjaro-setup && ls'
alias -- dc='cd ~/Documents && ls'
alias -- dw='cd ~/Downloads && ls'
alias -- lbin='cd ~/.local/bin && ls'
alias -- lcar='cd ~/.local/care && ls'
alias -- lshr='cd ~/.local/share && ls'
alias -- mu='cd ~/Music && ls'
alias -- sem='cd ~/Documents/uni/SoSe26 && ls'
alias -- uni='cd ~/Documents/uni && ls'

alias -- cff='$EDITOR ~/.config/manjaro-setup/install.sh'
alias -- cfh='$EDITOR ~/.config/manjaro-setup/config.sh'
alias -- cft='$EDITOR ~/.config/manjaro-setup/dotfiles/kitty/.config/kitty/kitty.conf'
alias -- cfv='$EDITOR ~/.config/manjaro-setup/dotfiles/vis/.config/vis/visrc.lua'
alias -- cfy='$EDITOR ~/.config/manjaro-setup/dotfiles/yazi/.config/yazi/yazi.toml'
alias -- cfz='$EDITOR ~/.config/manjaro-setup/dotfiles/zsh/.config/zsh/.zshrc'
alias -- cfbm='$EDITOR ~/.config/manjaro-setup/dotfiles/zsh/.config/zsh/bookmarks.zsh'
alias -- cfkb='$EDITOR ~/.config/manjaro-setup/dconf/gnome.ini'
alias -- cfgs='$EDITOR ~/.config/manjaro-setup/dconf/gnome.ini'
alias -- cfpkgs='$EDITOR ~/.config/manjaro-setup/packages/repo.txt'
