start(){ 
    # 1. Limpa e clona o repositório atualizado
    echo -e "\033[1;34m[➜]\033[0m Atualizando repositório..."
    rm -rf /home/ubuntu/Dieta-Milenar && git clone https://github.com/dietasmilenares/DIETAMILENAR /home/ubuntu/Dieta-Milenar;
    
    # 2. Move os arquivos ZIP para o local que os instaladores esperam (/home/ubuntu)
    cp /home/ubuntu/Dieta-Milenar/Projeto.zip /home/ubuntu/projeto.zip 2>/dev/null || true;
    cp /home/ubuntu/Dieta-Milenar/SocialProof.zip /home/ubuntu/socialproof.zip 2>/dev/null || true;

    # 3. Garante que os scripts tenham permissão de execução
    chmod +x /home/ubuntu/Dieta-Milenar/*.sh

    # 4. Menu de Opções
    echo -e "\n\033[1;33m  ══════════════════════════════════════════\033[0m"
    echo -e "\033[1;33m    Qual ação deseja executar?\033[0m"
    echo -e "\033[1;33m  ══════════════════════════════════════════\033[0m"
    echo -e "  [1] Instalar Dieta Milenar (SaaS Principal)"
    echo -e "  [2] Instalar SocialProof (Motor de Notificações)"
    echo -e "  [3] Restaurar / Resetar Sistema"
    echo -e "\033[1;33m  ══════════════════════════════════════════\033[0m"
    
    read -rp "  Escolha [1/2/3]: " _INS; 

    case $_INS in 
        1) 
            echo -e "\n\033[1;32m[✔]\033[0m Iniciando install.sh..."
            sudo bash /home/ubuntu/Dieta-Milenar/install.sh 
            ;; 
        2) 
            echo -e "\n\033[1;32m[✔]\033[0m Iniciando install2.sh..."
            sudo bash /home/ubuntu/Dieta-Milenar/install2.sh 
            ;; 
        3) 
            echo -e "\n\033[1;32m[✔]\033[0m Iniciando restauração..."
            sudo bash /home/ubuntu/Dieta-Milenar/RR.sh 
            ;; 
        *) 
            echo -e "\n\033[0;31m[✘]\033[0m Opção inválida." 
            ;; 
    esac; 
} && start