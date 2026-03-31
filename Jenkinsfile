pipeline {
    agent any 
    
    environment {
        IBMI_HOST = 'pub400.com'
        IBMI_SSH_PORT = '2222'
    }
    
    stages {
        stage('Connect and test') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'pub400-auth', 
                                                 usernameVariable: 'IBMI_USER', 
                                                 passwordVariable: 'IBMI_PASSWORD')]) {
                    nodejs('NodeJS_25') { 
                        sh """
                            # Install the tool if it doesn't exist
                            npm install -g @ibm/ibmi-ci
                            
                            # Run the command
                            ici --cl "DSPSYSVAL QDATE"
                        """
                    }
                }
            }
        }
    }
}