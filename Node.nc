/*
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
          call LinkStateRouting.routePacket(myMsg);
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
            
            call NeighborDiscovery.discover(myMsg);
            call NeighborDiscovery.printNeighbors();
            dbg(GENERAL_CHANNEL, "Routing packet\n");
            call LinkStateRouting.routePacket(myMsg);
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

*/
#include <Timer.h>
#include <string.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"

module Node {
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
   pack sendPackage;  // Packet to be used for sending

   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

   // Boot event: Called when the node has booted
   event void Boot.booted() {
      dbg(GENERAL_CHANNEL, "Node Booted\n");

      // Start the radio (AMControl)
      call AMControl.start();
   }

   // Radio start event: Called when the radio is successfully started
   event void AMControl.startDone(error_t err) {
      if (err == SUCCESS) {
         dbg(GENERAL_CHANNEL, "Radio On\n");

         // Start Neighbor Discovery
         call NeighborDiscovery.start();
         dbg(GENERAL_CHANNEL, "Starting Neighbor Discovery\n");

         // Start Link State Routing
         call LinkStateRouting.start();
         dbg(GENERAL_CHANNEL, "Starting Link State Routing\n");

      } else {
         // If starting the radio fails, retry
         dbg(GENERAL_CHANNEL, "Radio start failed, retrying\n");
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err) {}

   // Packet receive event: Handles incoming packets
   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
      if (len == sizeof(pack)) {
         pack* myMsg = (pack*) payload;

         // Handle Neighbor Discovery Packets (PING/PINGREPLY)
         if (myMsg->dest == 0) {
            dbg(GENERAL_CHANNEL, "Neighbor Discovery Packet received\n");

            // Call Neighbor Discovery to handle the packet
            call NeighborDiscovery.discover(myMsg);

            // Optionally print neighbors
            call NeighborDiscovery.printNeighbors();

         // Handle Link State Packets (PROTOCOL_LS)
         } else if (myMsg->protocol == PROTOCOL_LS) {
            dbg(GENERAL_CHANNEL, "Link State Packet received\n");

            // Call Link State Routing to handle the Link State Packet
            call LinkStateRouting.handleLS(myMsg);

         // Handle other routing packets
         } else {
            dbg(GENERAL_CHANNEL, "Routing packet\n");

            // Route the packet using Link State Routing
            call LinkStateRouting.routePacket(myMsg);
         }

         return msg;
      }

      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
   }

   // Command Handler: Handle PING command
   event void CommandHandler.ping(uint16_t destination, uint8_t *payload) {
      dbg(GENERAL_CHANNEL, "Command Handler: PING received\n");

      // Send a PING using Link State Routing
      call LinkStateRouting.ping(destination, payload);
   }

   // Command Handler: Print Neighbors
   event void CommandHandler.printNeighbors() {
      call NeighborDiscovery.printNeighbors();
   }

   // Command Handler: Print Routing Table
   event void CommandHandler.printRouteTable() {
      call LinkStateRouting.printRouteTable();
   }

   // Helper function to create a packet
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length) {
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }
}
