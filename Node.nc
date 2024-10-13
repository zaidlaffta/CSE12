
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
   uses interface Flooding;
   uses interface NeighborDiscovery;
   uses interface LinkStateRouting;
}

implementation {
   pack sendPackage;

   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

   event void Boot.booted() {
      dbg(GENERAL_CHANNEL, "Node Booted\n");
      call AMControl.start();
   }

   event void AMControl.startDone(error_t err) {
      if(err == SUCCESS) {
         dbg(GENERAL_CHANNEL, "Radio On\n");
         call NeighborDiscovery.start();
         dbg(GENERAL_CHANNEL, "Starting Neighbor Discovery\n");
         call LinkStateRouting.start();
         dbg(GENERAL_CHANNEL, "Starting Link State Routing\n");
      } else {
         dbg(GENERAL_CHANNEL, "Radio start failed, retrying\n");
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err) {}

   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
      if(len == sizeof(pack)) {
         pack* myMsg = (pack*) payload;

         if (myMsg->dest == 0) {
            dbg(GENERAL_CHANNEL, "Neighbor Discovery Packet received\n");
            call NeighborDiscovery.discover(myMsg);
            call NeighborDiscovery.printNeighbors();
         } else if(myMsg->protocol == PROTOCOL_LS) {
            dbg(GENERAL_CHANNEL, "Link State Packet received\n");
            call LinkStateRouting.handleLS(myMsg);       
         } else {
            dbg(GENERAL_CHANNEL, "Routing packet\n");
            call LinkStateRouting.routePacket(myMsg);
         }
         return msg;
      }

      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
   }

   event void CommandHandler.ping(uint16_t destination, uint8_t *payload) {
      dbg(GENERAL_CHANNEL, "Command Handler: PING received\n");
      call LinkStateRouting.ping(destination, payload);                  
   }

   event void CommandHandler.printNeighbors() {
      call NeighborDiscovery.printNeighbors();
   }

   event void CommandHandler.printRouteTable() {
      call LinkStateRouting.printRouteTable();
   }

   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length) {
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }
}
