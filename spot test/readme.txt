Om ervoor te zorgen dat het script automatisch wordt uitgevoerd bij de eerste opstart, 
voeg je een regel toe aan de rc.local van de Raspberry Pi. 
Plaats de volgende regel aan het einde van /etc/rc.local (voor exit 0):

/home/pi/setup.sh && rm /home/pi/setup.sh

Deze regel zorgt ervoor dat het script wordt uitgevoerd en daarna zichzelf verwijdert.