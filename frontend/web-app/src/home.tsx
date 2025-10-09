import {
    Card,
    CardContent,
    CardDescription,
    CardHeader,
    CardTitle
} from "@/components/ui/card";

import Navbar from "./components/navbar";
import blogPost1 from "./assets/picture.jpg";
import blogPost2 from "./assets/robots.png";

  const blogPosts = [
    {
      title: "New PROFILE PICTURE!!!",
      image: blogPost1,
      content: "Look at my new and beautiful profile picture! I just uploaded it using the settings page.",
      username: "handsomeguy995"
    },
    {
      title: "My first blog post",
      image: blogPost2,
      content: `
Did you know that websites sometimes tell search engines what not to look at?  
This is done using a special file. I just found out that this website has one!
`,
      username: "OngTengWee5000"
    }
  ]


function Home() {
    return (
        <div className="flex flex-col justify-center items-center">
            <Navbar />
            <div className="flex flex-col gap-12 mt-12 justify-center items-center">
                {blogPosts.map(post => (
                    <Card key={post.username} className="w-1/2">
                        <CardHeader>
                            <CardTitle>{post.title}</CardTitle>
                            <CardDescription>{post.username}</CardDescription>
                        </CardHeader>
                        <CardContent>
                            <img src={post.image} alt="image" className="w-50 rounded-md mx-auto my-5"/>
                            <p>{post.content}</p>
                        </CardContent>
                    </Card> 
                ))}
            </div>
        </div>
    )
}

export default Home;