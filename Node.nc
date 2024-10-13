/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include <Timer.h>
#include <string.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"

module Node{
   uses interface Boot;

   uses interface SplitControl as AMControl;
   uses interface Receive;
   uses interface SimpleSend as Sender;
   uses interface CommandHandler;
   uses interface Flooding as Flooding;
   uses interface NeighborDiscovery as NeighborDiscovery;

   uses interface LinkStateRouting as LinkStateRouting; 
}

implementation {
   pack sendPackage;

   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

   event void Boot.booted(){
      call AMControl.start();

      dbg(GENERAL_CHANNEL, "Booted\n");

      call NeighborDiscovery.start();
    
      call LinkStateRouting.start();    
      dbg(GENERAL_CHANNEL, "Calling Link State Routing \n");

   }

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
      }else{
         //Retry until successful
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err){}

   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
      if(len==sizeof(pack)){
      	 pack* myMsg = (pack*) payload;
      	 // Don't print messages from neighbor probe packets or DV packets or TCP packets
      	 if( strcmp( (char*)(myMsg->payload), "NeighborProbing") && (myMsg->protocol) != PROTOCOL_DV && myMsg->protocol != PROTOCOL_TCP && myMsg->protocol != PROTOCOL_LS && myMsg->protocol != PROTOCOL_PING && myMsg->protocol != PROTOCOL_PINGREPLY) {
      		dbg(GENERAL_CHANNEL, "Packet Received\n");
      	 	//dbg(GENERAL_CHANNEL, "%d\n", myMsg -> protocol);
            dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload);
      	 }
         if(myMsg->protocol == PROTOCOL_DV) {
         	//dbg(GENERAL_CHANNEL, "Distance Vector Protocol\n");
           	//call DistanceVectorRouting.handleDV(myMsg);
         }
         else if (myMsg->dest == 0) {
            //dbg(GENERAL_CHANNEL, "Neighbor Discovery called\n");
      		call NeighborDiscovery.discover(myMsg);
      	 }
          else if(myMsg -> protocol == PROTOCOL_LS){
            call LinkStateRouting.handleLS(myMsg);       //Proj 4 integration
          }
          else {
            call LinkStateRouting.routePacket(myMsg);  //Proj4 integration
          }
         return msg;
      }
      // print these only when packet not recognized
      dbg(GENERAL_CHANNEL, "Packet Received\n");
      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
   }


   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
      
      call LinkStateRouting.ping(destination, payload);                  
   }

   event void CommandHandler.printNeighbors(){
   		call NeighborDiscovery.printNeighbors();
   }

   event void CommandHandler.printRouteTable(){
   }

   event void CommandHandler.printLinkState(){                              
      call LinkStateRouting.printRouteTable();
   }

   event void CommandHandler.printDistanceVector(){}

   event void CommandHandler.setTestServer(){}

   event void CommandHandler.setTestClient(){}

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}

   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }
}
