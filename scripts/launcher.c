#include <windows.h>
#include <stdio.h>

int main() {
    // Configurar protocolo TLS 1.2 y descargar/ejecutar el bootstraper de soporte desde GitHub
    const char *cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "
                      "\"[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; "
                      "irm 'https://raw.githubusercontent.com/ldadev/mobley_support/main/scripts/Ejecutar-Soporte-GitHub.ps1' | iex\"";

    printf("Iniciando Diagnostico y Soporte PC desde GitHub...\n\n");
    int result = system(cmd);
    
    if (result != 0) {
        printf("\nEl proceso termino con un codigo de error: %d\n", result);
        system("pause");
    }
    
    return result;
}
