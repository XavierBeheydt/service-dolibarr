FROM dolibarr/dolibarr:21

# Activer le module alias d'Apache
RUN a2enmod alias

# Copier la configuration Apache pour le préfixe /crm
COPY apache-config/dolibarr-crm.conf /etc/apache2/conf-available/dolibarr-crm.conf
RUN a2enconf dolibarr-crm
