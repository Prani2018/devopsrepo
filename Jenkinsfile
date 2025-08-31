pipeline {
    agent {
        label 'JavaBuildServer'
    }
    tools {
        maven 'localMaven'
    }

stages{
        stage('Build'){
            steps {
                sh 'mvn clean package'
            }
            post {
                success {
                    echo 'Archiving the artifacts'
                    archiveArtifacts artifacts: '**/target/*.war'
                }
            }
        }

        stage ('Deployments'){
                    steps {
                        sh "scp **/*.war jenkins@${params.tomcat_stag}:/usr/share/tomcat/webapps"
                        deploy adapters: [ tomcat9(credentialsId: 'tomcatcred', path:'', url: 'http://54.165.43.152:8080/', contextPath: '', war: '**/*.war' )]
                    }
            }
        }
}
