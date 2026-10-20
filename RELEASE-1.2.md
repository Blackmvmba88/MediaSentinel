Versión 1.2 (build 3). Instalación: /Applications/Media Sentinel.app.

Compilada con `zsh build.sh`. Firma ad hoc verificada por el build; cambia cdhash respecto a 1.1. No usa permisos TCC.

Prueba funcional `--self-test-stop`: PASS, detectó afplay y terminó la reproducción por SIGTERM. No se terminó el proceso Quick Look del usuario durante la prueba.

Recuperación local: build/recovery-1.1.app (fuera del control de versiones). Restaurar ese bundle a la ruta de instalación si la nueva versión falla al abrir o detener audio. Sin datos persistentes que migrar.
