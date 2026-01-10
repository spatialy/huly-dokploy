# Huly V7 Dokploy Template

## F*ck me, after spending 50 days trying to deploy Huly as a non-coder I finally did it. Here's how using Dokploy:

---

## Prerequisites: Get Your Server IP and Create Domains

### Step 1: Find Your Server IP

SSH into your server and run:
```bash
curl ifconfig.me
```
This will show your server IP (example: `88.222.521.3`). Write it down - you'll need it.

### Step 2: Create Free Domains

1. Go to https://www.dynu.com/ and create an account
2. Go to **Control Panel**
3. Go to **DDNS Services**
4. Click **Add**

**Create Huly Domain:**
1. Under "Option 1: Use Our Domain Name", enter a name like `huly`
2. Click **Add**
3. Find the **IPv4 Address** field - it will have a random IP
4. Replace it with YOUR server IP (e.g., `88.222.521.3`)
5. Click **Save**

**Create LiveKit Domain:**
1. Click **Add** again
2. Enter a name like `livekit`
3. Click **Add**
4. Replace the **IPv4 Address** with YOUR server IP
5. Click **Save**

Now you have 2 domains:
- `huly.dynu.net` → points to your server
- `livekit.dynu.net` → points to your server

---

## Part 1: Deploy Huly

1. In Dokploy, clikc create project call it somehow like "Huly"  and clikc create.
then clikc create service and select template.
 go to **Templates** and add this repository in the Base url filed. URL "https://raw.githubusercontent.com/shali1995/dok/main"
then clikc create.
2. Select the **Huly V7** template
3. Go to **Environment** tab and change:
   ```
   HOST_ADDRESS=huly.dynu.net
   ```
   (Replace with your actual domain)
4. Go to **Domains** tab:
   - Change the domain from the auto-generated one to yours
   - Enable **HTTPS**
5. Click **Deploy**

🎉 **Huly is now running!** 

---

## Part 2: Enable Video Calls (Optional)

Video calls require LiveKit. Here's how to set it up:

### Step 1: Deploy LiveKit

1. In Dokploy, create a **new app**
2. Go to **Templates** and search for **LiveKit**
3. Select and create the LiveKit template
4. Go to **Environment** tab, change:
   ```
   LIVEKIT_URL=livekit.dynu.net
   ```
   (Replace with your LiveKit domain)

5. Go to **Domains** tab - you'll see 3 domains
6. Find the one with **Port: 5349**, click edit:
   - Change to `livekit.dynu.net` (your LiveKit domain)
   - Enable **HTTPS**
   - Click **Save**
   
7. Find the one with **Port: 7880**, click edit:
   - Change to `livekit.dynu.net` (your LiveKit domain)
   - Enable **HTTPS**
   - Click **Save**

8. Click **Deploy**

### Step 2: Connect Huly to LiveKit

1. In Dokploy, go to your **LiveKit** app
2. Go to **Environment** tab
3. Find and copy these values:
   ```
   API_KEY=<your_generated_key>
   API_SECRET=<your_generated_secret>
   ```

4. Go back to your **Huly** app
5. Go to **Environment** tab
6. Find these fields and update them:
   ```
   LIVEKIT_HOST=livekit.dynu.net
   LIVEKIT_API_KEY=<paste your API_KEY here>
   LIVEKIT_API_SECRET=<paste your API_SECRET here>
   ```

7. Click **Save** and **Deploy**

🎉 **Video calls are now enabled!**

---

## Important Notes

- ⚠️ You need **2 separate subdomains**: one for Huly, one for LiveKit
- ⚠️ Both domains must point to your server IP
- ⚠️ HTTPS must be enabled on both domains
- ⏳ Wait 1-2 minutes for DNS to propagate before deploying
- 🔄 If something doesn't work, try redeploying

---

## Troubleshooting

### Login doesn't persist after refresh
- Make sure HTTPS is enabled
- Check that HOST_ADDRESS matches your actual domain
- Redeploy the app

### Video calls not working
- Check that both LiveKit domains (ports 5349 and 7880) have HTTPS enabled
- Verify LIVEKIT_HOST, LIVEKIT_API_KEY, and LIVEKIT_API_SECRET are correct
- Make sure your LiveKit domain is different from your Huly domain

### 502 Bad Gateway
- Wait a few seconds and refresh
- If persists, go to Deployments tab and redeploy

---

## Credits

This template was created after countless hours of debugging. If it helps you, give it a ⭐!
